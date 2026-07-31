package app.tachiaz.runtime;

import java.io.File;
import java.lang.reflect.Array;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.net.URL;
import java.net.URLDecoder;
import java.net.URLClassLoader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.LinkedHashSet;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public final class ExtensionHost {
    private static final ConcurrentHashMap<String, LoadedExtension> EXTENSIONS =
        new ConcurrentHashMap<>();
    private static boolean compatibilityInitialized;
    private static Object compatibilityApplication;

    private ExtensionHost() {
    }

    /**
     * Stable JNI entry point. Exceptions are encoded into the response rather
     * than crossing the native boundary.
     */
    public static String dispatch(String requestJson) {
        try {
            Map<String, String> request = MiniJson.parseObject(requestJson);
            String operation = require(request, "operation");
            switch (operation) {
                case "ping":
                    return ping();
                case "inspectExtension":
                    return inspectExtension(request);
                case "loadExtension":
                    return loadExtension(request);
                case "initializeCompatibility":
                    return initializeCompatibility();
                case "getPopularManga":
                    return getPopularManga(request);
                case "getLatestUpdates":
                    return getLatestUpdates(request);
                case "searchManga":
                    return searchManga(request);
                case "getSearchFilters":
                    return getSearchFilters(request);
                case "getSettings":
                    return getSettings(request);
                case "setSetting":
                    return setSetting(request);
                case "getMangaUpdate":
                    return getMangaUpdate(request);
                case "getPageList":
                    return getPageList(request);
                case "listSources":
                    return listSources(request);
                case "invoke":
                    return invoke(request);
                case "unloadExtension":
                    return unloadExtension(request);
                case "decodeBackup":
                    return decodeBackup(request);
                default:
                    throw new IllegalArgumentException(
                        "Unsupported operation: " + operation
                    );
            }
        } catch (Throwable error) {
            return MiniJson.response(false, null, describe(error), null);
        }
    }

    private static String ping() {
        Map<String, String> metadata = new LinkedHashMap<>();
        metadata.put("runtime", "OpenJDK/mobile Zero");
        metadata.put("javaVersion", System.getProperty("java.version"));
        metadata.put(
            "maximumClassVersion",
            Integer.toString(JarBytecodeValidator.runtimeClassVersion())
        );
        return MiniJson.response(true, "pong", null, metadata);
    }

    private static String inspectExtension(Map<String, String> request)
        throws Exception {
        File jar = new File(require(request, "jarPath"));
        KeiyoushiJarMetadata.Metadata metadata =
            KeiyoushiJarMetadata.inspect(jar);
        Map<String, String> response = metadataMap(metadata);
        return MiniJson.response(true, metadata.entryClass, null, response);
    }

    private static String loadExtension(Map<String, String> request)
        throws Exception {
        String extensionId = require(request, "extensionId");
        File jar = new File(require(request, "jarPath"));
        KeiyoushiJarMetadata.Metadata metadata =
            KeiyoushiJarMetadata.inspect(jar);
        KeiyoushiJarMetadata.requireSupportedLibrary(metadata);
        String entryClass = request.get("entryClass");
        if (entryClass == null || entryClass.isEmpty()) {
            entryClass = metadata.entryClass;
        }

        initializeSuwayomiIfPresent();
        JarBytecodeValidator.validate(jar);
        URLClassLoader loader = new URLClassLoader(
            new URL[] { jar.toURI().toURL() },
            ExtensionHost.class.getClassLoader()
        );

        Object instance;
        List<Object> sources;
        try {
            Class<?> type = Class.forName(entryClass, true, loader);
            instance = type.getDeclaredConstructor().newInstance();
            sources = createSources(instance);
        } catch (Throwable error) {
            loader.close();
            throw error;
        }

        LoadedExtension replacement =
            new LoadedExtension(loader, instance, sources);
        LoadedExtension previous = EXTENSIONS.put(extensionId, replacement);
        if (previous != null) {
            previous.close();
        }
        Map<String, String> response = new LinkedHashMap<>();
        response.put("sourceCount", Integer.toString(sources.size()));
        return MiniJson.response(true, entryClass, null, response);
    }

    @SuppressWarnings("unchecked")
    private static List<Object> createSources(Object entry) throws Exception {
        try {
            Object value = entry.getClass()
                .getMethod("createSources")
                .invoke(entry);
            if (!(value instanceof List)) {
                throw new IllegalArgumentException(
                    "SourceFactory.createSources did not return a List"
                );
            }
            List<Object> sources = new ArrayList<>((List<Object>) value);
            if (sources.isEmpty()) {
                throw new IllegalArgumentException(
                    "SourceFactory returned no sources"
                );
            }
            return sources;
        } catch (NoSuchMethodException notAFactory) {
            List<Object> sources = new ArrayList<>();
            sources.add(entry);
            return sources;
        } catch (InvocationTargetException error) {
            throw rethrow(error.getCause());
        }
    }

    private static String initializeCompatibility() throws Exception {
        boolean initialized = initializeSuwayomiIfPresent();
        Map<String, String> metadata = new LinkedHashMap<>();
        metadata.put(
            "compatibility",
            initialized ? "suwayomi-androidcompat" : "none"
        );
        return MiniJson.response(true, "initialized", null, metadata);
    }

    /**
     * Initializes the Suwayomi source API and AndroidCompat without creating a
     * compile-time dependency from this stable host facade. This keeps fixture
     * tests and host-only tools runnable while allowing the app bundle to
     * supply the pinned compatibility JAR set at runtime.
     */
    private static synchronized boolean initializeSuwayomiIfPresent()
        throws Exception {
        if (compatibilityInitialized) {
            return true;
        }

        ClassLoader loader = ExtensionHost.class.getClassLoader();
        Class<?> appType;
        try {
            appType = Class.forName("eu.kanade.tachiyomi.App", true, loader);
        } catch (ClassNotFoundException unavailable) {
            return false;
        }

        Object app = appType.getDeclaredConstructor().newInstance();
        Class<?> applicationType =
            Class.forName("android.app.Application", true, loader);
        Class<?> moduleType =
            Class.forName("org.koin.core.module.Module", true, loader);

        Object appModule = invokeStatic(
            loader,
            "eu.kanade.tachiyomi.AppModuleKt",
            "createAppModule",
            new Class<?>[] { applicationType },
            app
        );
        Object androidCompatModule = invokeStatic(
            loader,
            "xyz.nulldev.androidcompat.AndroidCompatModuleKt",
            "androidCompatModule",
            new Class<?>[0]
        );
        Object configModule = invokeStatic(
            loader,
            "xyz.nulldev.ts.config.ConfigManagerModuleKt",
            "configManagerModule",
            new Class<?>[0]
        );

        Class<?> koinApplicationType =
            Class.forName("org.koin.core.KoinApplication", true, loader);
        Object companion = koinApplicationType.getField("Companion").get(null);
        Object koin = companion.getClass().getMethod("init").invoke(companion);
        Object modules = Array.newInstance(moduleType, 3);
        Array.set(modules, 0, appModule);
        Array.set(modules, 1, androidCompatModule);
        Array.set(modules, 2, configModule);
        koinApplicationType
            .getMethod("modules", modules.getClass())
            .invoke(koin, modules);

        Class<?> globalContextType =
            Class.forName("org.koin.core.context.GlobalContext", true, loader);
        Object globalContext = globalContextType.getField("INSTANCE").get(null);
        boolean koinStarted = false;
        try {
            globalContextType
                .getMethod("startKoin", koinApplicationType)
                .invoke(globalContext, koin);
            koinStarted = true;

            Object initializer = Class.forName(
                "xyz.nulldev.androidcompat.AndroidCompatInitializer",
                true,
                loader
            ).getDeclaredConstructor().newInstance();
            initializer.getClass().getMethod("init").invoke(initializer);

            Object androidCompat = Class.forName(
                "xyz.nulldev.androidcompat.AndroidCompat",
                true,
                loader
            ).getDeclaredConstructor().newInstance();
            androidCompat.getClass()
                .getMethod("startApp", applicationType)
                .invoke(androidCompat, app);
        } catch (Throwable error) {
            if (koinStarted) {
                globalContextType
                    .getMethod("stopKoin")
                    .invoke(globalContext);
            }
            throw rethrow(error);
        }

        compatibilityInitialized = true;
        compatibilityApplication = app;
        return true;
    }

    private static Object invokeStatic(
        ClassLoader loader,
        String className,
        String methodName,
        Class<?>[] parameterTypes,
        Object... arguments
    ) throws Exception {
        Class<?> type = Class.forName(className, true, loader);
        return type.getMethod(methodName, parameterTypes)
            .invoke(null, arguments);
    }

    private static String getPopularManga(Map<String, String> request)
        throws Exception {
        return getPagedManga(request, "getPopularManga");
    }

    private static String getLatestUpdates(Map<String, String> request)
        throws Exception {
        return getPagedManga(request, "getLatestUpdates");
    }

    private static String getPagedManga(
        Map<String, String> request,
        String methodName
    ) throws Exception {
        String extensionId = require(request, "extensionId");
        int page = Integer.parseInt(require(request, "argument"));
        if (page < 1) {
            throw new IllegalArgumentException("Page must be at least 1");
        }

        LoadedExtension extension = EXTENSIONS.get(extensionId);
        if (extension == null) {
            throw new IllegalArgumentException(
                "Extension is not loaded: " + extensionId
            );
        }

        Object mangasPage = invokeSuspend(
            extension.source(request.get("sourceId")),
            methodName,
            new Class<?>[] { int.class },
            page
        );

        return MiniJson.response(
            true,
            serializeMangasPage(mangasPage),
            null,
            null
        );
    }

    private static String searchManga(Map<String, String> request)
        throws Exception {
        String extensionId = require(request, "extensionId");
        int page = Integer.parseInt(require(request, "argument"));
        String query = defaultValue(request.get("query"), "");
        if (page < 1) {
            throw new IllegalArgumentException("Page must be at least 1");
        }

        LoadedExtension extension = EXTENSIONS.get(extensionId);
        if (extension == null) {
            throw new IllegalArgumentException(
                "Extension is not loaded: " + extensionId
            );
        }

        Object source = extension.source(request.get("sourceId"));
        Object filters = getter(source, "getFilterList");
        applyFilterStates(filters, request.get("filterStates"));
        Object mangasPage = invokeSuspend(
            source,
            "getSearchManga",
            new Class<?>[] {
                int.class,
                String.class,
                filters.getClass()
            },
            page,
            query,
            filters
        );
        return MiniJson.response(
            true,
            serializeMangasPage(mangasPage),
            null,
            null
        );
    }

    private static String getSearchFilters(Map<String, String> request)
        throws Exception {
        Object source = requireSource(request);
        Object filters = getter(source, "getFilterList");
        return MiniJson.response(
            true,
            serializeFilters(filters),
            null,
            null
        );
    }

    @SuppressWarnings("unchecked")
    private static String serializeFilters(Object filters) throws Exception {
        List<Object> list = (List<Object>) filters;
        List<String> serialized = new ArrayList<>();
        for (int index = 0; index < list.size(); index++) {
            serializeFilter(
                list.get(index),
                Integer.toString(index),
                null,
                serialized
            );
        }
        StringBuilder output = new StringBuilder("[");
        for (int index = 0; index < serialized.size(); index++) {
            if (index > 0) {
                output.append(',');
            }
            output.append(serialized.get(index));
        }
        return output.append(']').toString();
    }

    @SuppressWarnings("unchecked")
    private static void serializeFilter(
        Object filter,
        String path,
        String parentName,
        List<String> output
    ) throws Exception {
        String name = String.valueOf(getter(filter, "getName"));
        String title = parentName == null || parentName.isEmpty()
            ? name
            : parentName + " — " + name;
        ClassLoader loader = ExtensionHost.class.getClassLoader();
        if (isFilterType(loader, filter, "Group")) {
            List<Object> children = (List<Object>) getter(filter, "getState");
            for (int index = 0; index < children.size(); index++) {
                serializeFilter(
                    children.get(index),
                    path + "." + index,
                    title,
                    output
                );
            }
            return;
        }
        if (isFilterType(loader, filter, "Separator")) {
            return;
        }
        if (isFilterType(loader, filter, "Header")) {
            output.add(filterJson(path, "note", title, null, null, null));
            return;
        }
        if (isFilterType(loader, filter, "Text")) {
            output.add(filterJson(
                path,
                "text",
                title,
                null,
                getter(filter, "getState"),
                null
            ));
            return;
        }
        if (isFilterType(loader, filter, "CheckBox")) {
            output.add(filterJson(
                path,
                "check",
                title,
                null,
                getter(filter, "getState"),
                "false"
            ));
            return;
        }
        if (isFilterType(loader, filter, "TriState")) {
            output.add(filterJson(
                path,
                "check",
                title,
                null,
                getter(filter, "getState"),
                "true"
            ));
            return;
        }
        if (isFilterType(loader, filter, "Sort")) {
            Object state = getter(filter, "getState");
            Object index = state == null ? null : getter(state, "getIndex");
            Object ascending = state == null
                ? null
                : getter(state, "getAscending");
            output.add(filterJson(
                path,
                "sort",
                title,
                (Object[]) getter(filter, "getValues"),
                index,
                ascending
            ));
            return;
        }
        if (isFilterType(loader, filter, "Select")) {
            List<String> values = (List<String>) getter(
                filter,
                "getDisplayValues"
            );
            output.add(filterJson(
                path,
                "select",
                title,
                values.toArray(new Object[0]),
                getter(filter, "getState"),
                null
            ));
        }
    }

    private static boolean isFilterType(
        ClassLoader loader,
        Object filter,
        String nestedName
    ) throws Exception {
        return Class.forName(
            "eu.kanade.tachiyomi.source.model.Filter$" + nestedName,
            true,
            loader
        ).isInstance(filter);
    }

    private static String filterJson(
        String id,
        String type,
        String name,
        Object[] options,
        Object defaultValue,
        Object auxiliary
    ) {
        StringBuilder output = new StringBuilder("{");
        appendJsonField(output, "id", id, false);
        appendJsonField(output, "type", type, true);
        appendJsonField(output, "name", name, true);
        if (options != null) {
            output.append(",\"options\":[");
            for (int index = 0; index < options.length; index++) {
                if (index > 0) {
                    output.append(',');
                }
                output.append('"')
                    .append(MiniJson.escapeValue(String.valueOf(options[index])))
                    .append('"');
            }
            output.append(']');
        }
        if (defaultValue != null) {
            appendJsonField(
                output,
                "defaultValue",
                defaultValue,
                true
            );
        }
        if (auxiliary != null) {
            appendJsonField(output, "auxiliary", auxiliary, true);
        }
        return output.append('}').toString();
    }

    @SuppressWarnings("unchecked")
    private static void applyFilterStates(
        Object filters,
        String encodedStates
    ) throws Exception {
        if (encodedStates == null || encodedStates.isEmpty()) {
            return;
        }
        List<Object> roots = (List<Object>) filters;
        String[] lines = encodedStates.split("\\n");
        for (String line : lines) {
            String[] fields = line.split("\\t", -1);
            if (fields.length < 3) {
                continue;
            }
            Object filter = filterAtPath(roots, fields[0]);
            String kind = fields[1];
            String value = URLDecoder.decode(
                fields[2],
                StandardCharsets.UTF_8.name()
            );
            Object state;
            switch (kind) {
                case "text":
                    state = value;
                    break;
                case "check":
                case "select":
                    state = Integer.valueOf(value);
                    if ("check".equals(kind) && isFilterType(
                        ExtensionHost.class.getClassLoader(),
                        filter,
                        "CheckBox"
                    )) {
                        state = Integer.parseInt(value) != 0;
                    }
                    break;
                case "sort":
                    boolean ascending =
                        fields.length > 3 &&
                        Boolean.parseBoolean(fields[3]);
                    Class<?> selection = Class.forName(
                        "eu.kanade.tachiyomi.source.model.Filter$Sort$Selection",
                        true,
                        ExtensionHost.class.getClassLoader()
                    );
                    state = selection
                        .getConstructor(int.class, boolean.class)
                        .newInstance(Integer.parseInt(value), ascending);
                    break;
                default:
                    continue;
            }
            filter.getClass()
                .getMethod("setState", Object.class)
                .invoke(filter, state);
        }
    }

    @SuppressWarnings("unchecked")
    private static Object filterAtPath(
        List<Object> roots,
        String path
    ) throws Exception {
        String[] components = path.split("\\.");
        Object filter = roots.get(Integer.parseInt(components[0]));
        for (int index = 1; index < components.length; index++) {
            List<Object> children =
                (List<Object>) getter(filter, "getState");
            filter = children.get(Integer.parseInt(components[index]));
        }
        return filter;
    }

    private static String getSettings(Map<String, String> request)
        throws Exception {
        Object source = requireSource(request);
        List<Object> preferences = sourcePreferences(source);
        StringBuilder output = new StringBuilder("[");
        int count = 0;
        for (Object preference : preferences) {
            String type = preferenceType(preference);
            String key = String.valueOf(getter(preference, "getKey"));
            if (type == null || key == null || "null".equals(key)) {
                continue;
            }
            if (count++ > 0) {
                output.append(',');
            }
            output.append('{');
            appendJsonField(output, "key", key, false);
            appendJsonField(
                output,
                "title",
                getter(preference, "getTitle"),
                true
            );
            appendJsonField(
                output,
                "summary",
                getter(preference, "getSummary"),
                true
            );
            appendJsonField(output, "type", type, true);
            appendJsonField(
                output,
                "enabled",
                getter(preference, "isEnabled"),
                true
            );
            appendJsonField(
                output,
                "currentValue",
                serializePreferenceValue(
                    getter(preference, "getCurrentValue")
                ),
                true
            );
            if ("select".equals(type) || "multiselect".equals(type)) {
                appendStringArray(
                    output,
                    "options",
                    (Object[]) getter(preference, "getEntries")
                );
                appendStringArray(
                    output,
                    "values",
                    (Object[]) getter(preference, "getEntryValues")
                );
            }
            output.append('}');
        }
        output.append(']');
        return MiniJson.response(true, output.toString(), null, null);
    }

    private static String setSetting(Map<String, String> request)
        throws Exception {
        Object source = requireSource(request);
        String key = require(request, "settingKey");
        String type = require(request, "settingType");
        String value = defaultValue(request.get("settingValue"), "");
        for (Object preference : sourcePreferences(source)) {
            if (!key.equals(String.valueOf(getter(preference, "getKey")))) {
                continue;
            }
            Object newValue;
            switch (type) {
                case "toggle":
                    newValue = Boolean.valueOf(value);
                    break;
                case "multiselect":
                    Set<String> values = new LinkedHashSet<>();
                    if (!value.isEmpty()) {
                        for (String item : value.split("\\n", -1)) {
                            values.add(item);
                        }
                    }
                    newValue = values;
                    break;
                default:
                    newValue = value;
                    break;
            }
            preference.getClass()
                .getMethod("saveNewValue", Object.class)
                .invoke(preference, newValue);
            return MiniJson.response(true, key, null, null);
        }
        throw new IllegalArgumentException(
            "Unknown extension preference: " + key
        );
    }

    @SuppressWarnings("unchecked")
    private static List<Object> sourcePreferences(Object source)
        throws Exception {
        ClassLoader loader = ExtensionHost.class.getClassLoader();
        Class<?> configurable = Class.forName(
            "eu.kanade.tachiyomi.source.ConfigurableSource",
            true,
            loader
        );
        if (!configurable.isInstance(source)) {
            return new ArrayList<>();
        }
        if (compatibilityApplication == null) {
            initializeSuwayomiIfPresent();
        }
        Class<?> context = Class.forName(
            "android.content.Context",
            true,
            loader
        );
        Class<?> screenType = Class.forName(
            "androidx.preference.PreferenceScreen",
            true,
            loader
        );
        Object screen = screenType
            .getConstructor(context)
            .newInstance(compatibilityApplication);
        source.getClass()
            .getMethod("setupPreferenceScreen", screenType)
            .invoke(source, screen);
        List<Object> preferences = (List<Object>) screenType
            .getMethod("getPreferences")
            .invoke(screen);
        Object sharedPreferences = getter(
            source,
            "getSourcePreferences"
        );
        Class<?> sharedPreferencesType = Class.forName(
            "android.content.SharedPreferences",
            true,
            loader
        );
        for (Object preference : preferences) {
            preference.getClass()
                .getMethod(
                    "setSharedPreferences",
                    sharedPreferencesType
                )
                .invoke(preference, sharedPreferences);
        }
        return preferences;
    }

    private static String preferenceType(Object preference)
        throws Exception {
        ClassLoader loader = ExtensionHost.class.getClassLoader();
        if (Class.forName(
            "androidx.preference.SwitchPreferenceCompat",
            true,
            loader
        ).isInstance(preference)) {
            return "toggle";
        }
        if (Class.forName(
            "androidx.preference.ListPreference",
            true,
            loader
        ).isInstance(preference)) {
            return "select";
        }
        if (Class.forName(
            "androidx.preference.MultiSelectListPreference",
            true,
            loader
        ).isInstance(preference)) {
            return "multiselect";
        }
        if (Class.forName(
            "androidx.preference.EditTextPreference",
            true,
            loader
        ).isInstance(preference)) {
            return "text";
        }
        return null;
    }

    private static String serializePreferenceValue(Object value) {
        if (!(value instanceof Set)) {
            return value == null ? null : String.valueOf(value);
        }
        StringBuilder output = new StringBuilder();
        for (Object item : (Set<?>) value) {
            if (output.length() > 0) {
                output.append('\n');
            }
            output.append(String.valueOf(item));
        }
        return output.toString();
    }

    private static void appendStringArray(
        StringBuilder output,
        String key,
        Object[] values
    ) {
        output.append(",\"")
            .append(MiniJson.escapeValue(key))
            .append("\":[");
        for (int index = 0; index < values.length; index++) {
            if (index > 0) {
                output.append(',');
            }
            output.append('"')
                .append(MiniJson.escapeValue(String.valueOf(values[index])))
                .append('"');
        }
        output.append(']');
    }

    private static String getMangaUpdate(Map<String, String> request)
        throws Exception {
        Object source = requireSource(request);
        ClassLoader loader = ExtensionHost.class.getClassLoader();
        Class<?> mangaType = Class.forName(
            "eu.kanade.tachiyomi.source.model.SManga",
            true,
            loader
        );
        Object manga = Class.forName(
            "eu.kanade.tachiyomi.source.model.SMangaImpl",
            true,
            loader
        ).getDeclaredConstructor().newInstance();
        setter(manga, "setUrl", String.class, require(request, "mangaURL"));
        setter(
            manga,
            "setTitle",
            String.class,
            defaultValue(request.get("mangaTitle"), "")
        );

        Object update = invokeSuspend(
            source,
            "getMangaUpdate",
            new Class<?>[] {
                mangaType,
                List.class,
                boolean.class,
                boolean.class
            },
            manga,
            new ArrayList<>(),
            true,
            true
        );
        return MiniJson.response(
            true,
            serializeMangaUpdate(update),
            null,
            null
        );
    }

    private static String getPageList(Map<String, String> request)
        throws Exception {
        Object source = requireSource(request);
        ClassLoader loader = ExtensionHost.class.getClassLoader();
        Class<?> chapterType = Class.forName(
            "eu.kanade.tachiyomi.source.model.SChapter",
            true,
            loader
        );
        Object chapter = Class.forName(
            "eu.kanade.tachiyomi.source.model.SChapterImpl",
            true,
            loader
        ).getDeclaredConstructor().newInstance();
        setter(
            chapter,
            "setUrl",
            String.class,
            require(request, "chapterURL")
        );
        setter(
            chapter,
            "setName",
            String.class,
            defaultValue(request.get("chapterName"), "")
        );
        Object pages = invokeSuspend(
            source,
            "getPageList",
            new Class<?>[] { chapterType },
            chapter
        );
        return MiniJson.response(
            true,
            serializePages(source, pages),
            null,
            null
        );
    }

    private static Object requireSource(Map<String, String> request)
        throws Exception {
        String extensionId = require(request, "extensionId");
        LoadedExtension extension = EXTENSIONS.get(extensionId);
        if (extension == null) {
            throw new IllegalArgumentException(
                "Extension is not loaded: " + extensionId
            );
        }
        return extension.source(request.get("sourceId"));
    }

    private static String listSources(Map<String, String> request)
        throws Exception {
        String extensionId = require(request, "extensionId");
        LoadedExtension extension = EXTENSIONS.get(extensionId);
        if (extension == null) {
            throw new IllegalArgumentException(
                "Extension is not loaded: " + extensionId
            );
        }

        StringBuilder output = new StringBuilder("[");
        for (int index = 0; index < extension.sources.size(); index++) {
            if (index > 0) {
                output.append(',');
            }
            Object source = extension.sources.get(index);
            output.append('{');
            appendJsonField(output, "id", getter(source, "getId"), false);
            appendJsonField(output, "name", getter(source, "getName"), true);
            appendJsonField(output, "lang", getter(source, "getLang"), true);
            appendJsonField(
                output,
                "supportsLatest",
                getter(source, "getSupportsLatest"),
                true
            );
            output.append('}');
        }
        output.append(']');
        return MiniJson.response(true, output.toString(), null, null);
    }

    static Object invokeSuspend(
        Object instance,
        String methodName,
        Class<?>[] parameterTypes,
        Object... arguments
    ) throws Exception {
        ClassLoader loader = ExtensionHost.class.getClassLoader();
        Class<?> continuationType =
            Class.forName("kotlin.coroutines.Continuation", true, loader);
        Class<?>[] suspendParameterTypes =
            new Class<?>[parameterTypes.length + 1];
        System.arraycopy(
            parameterTypes,
            0,
            suspendParameterTypes,
            0,
            parameterTypes.length
        );
        suspendParameterTypes[parameterTypes.length] = continuationType;

        CountDownLatch completion = new CountDownLatch(1);
        AtomicReference<Object> resumedValue = new AtomicReference<>();
        Object emptyContext = Class.forName(
            "kotlin.coroutines.EmptyCoroutineContext",
            true,
            loader
        ).getField("INSTANCE").get(null);

        InvocationHandler handler = (proxy, method, invocationArguments) -> {
            switch (method.getName()) {
                case "getContext":
                    return emptyContext;
                case "resumeWith":
                    resumedValue.set(invocationArguments[0]);
                    completion.countDown();
                    return null;
                case "toString":
                    return "TachiAZContinuation(" + methodName + ")";
                default:
                    return null;
            }
        };
        Object continuation = Proxy.newProxyInstance(
            continuationType.getClassLoader(),
            new Class<?>[] { continuationType },
            handler
        );

        Object[] suspendArguments = new Object[arguments.length + 1];
        System.arraycopy(
            arguments,
            0,
            suspendArguments,
            0,
            arguments.length
        );
        suspendArguments[arguments.length] = continuation;

        Object immediate;
        try {
            immediate = instance.getClass()
                .getMethod(methodName, suspendParameterTypes)
                .invoke(instance, suspendArguments);
        } catch (InvocationTargetException error) {
            throw rethrow(error.getCause());
        }

        Object suspended = enumConstant(
            Class.forName(
                "kotlin.coroutines.intrinsics.CoroutineSingletons",
                true,
                loader
            ),
            "COROUTINE_SUSPENDED"
        );
        Object result = immediate;
        if (immediate == suspended) {
            if (!completion.await(2, TimeUnit.MINUTES)) {
                throw new IllegalStateException(
                    "Extension operation timed out after 2 minutes"
                );
            }
            result = resumedValue.get();
        }

        try {
            Class.forName("kotlin.ResultKt", true, loader)
                .getMethod("throwOnFailure", Object.class)
                .invoke(null, result);
        } catch (InvocationTargetException error) {
            throw rethrow(error.getCause());
        }
        return result;
    }

    private static Object enumConstant(Class<?> type, String name) {
        Object[] constants = type.getEnumConstants();
        if (constants == null) {
            throw new IllegalArgumentException(
                type.getName() + " is not an enum"
            );
        }
        for (Object constant : constants) {
            if (((Enum<?>) constant).name().equals(name)) {
                return constant;
            }
        }
        throw new IllegalArgumentException(
            "Unknown " + type.getName() + " value: " + name
        );
    }

    private static Exception rethrow(Throwable error) throws Exception {
        if (error instanceof Exception) {
            return (Exception) error;
        }
        if (error instanceof Error) {
            throw (Error) error;
        }
        return new RuntimeException(error);
    }

    private static String serializeMangasPage(Object page) throws Exception {
        @SuppressWarnings("unchecked")
        List<Object> mangas = (List<Object>) page.getClass()
            .getMethod("getMangas")
            .invoke(page);
        boolean hasNextPage = (Boolean) page.getClass()
            .getMethod("getHasNextPage")
            .invoke(page);

        StringBuilder output = new StringBuilder("{\"mangas\":[");
        for (int index = 0; index < mangas.size(); index++) {
            if (index > 0) {
                output.append(',');
            }
            Object manga = mangas.get(index);
            appendManga(output, manga);
        }
        output.append("],\"hasNextPage\":")
            .append(hasNextPage)
            .append('}');
        return output.toString();
    }

    private static String serializeMangaUpdate(Object update) throws Exception {
        Object manga = getter(update, "getManga");
        @SuppressWarnings("unchecked")
        List<Object> chapters =
            (List<Object>) getter(update, "getChapters");
        StringBuilder output = new StringBuilder("{\"manga\":");
        appendManga(output, manga);
        output.append(",\"chapters\":[");
        for (int index = 0; index < chapters.size(); index++) {
            if (index > 0) {
                output.append(',');
            }
            Object chapter = chapters.get(index);
            output.append('{');
            appendJsonField(
                output,
                "url",
                getter(chapter, "getUrl"),
                false
            );
            appendJsonField(
                output,
                "name",
                getter(chapter, "getName"),
                true
            );
            appendJsonField(
                output,
                "chapterNumber",
                getter(chapter, "getChapter_number"),
                true
            );
            appendJsonField(
                output,
                "scanlator",
                getter(chapter, "getScanlator"),
                true
            );
            appendJsonField(
                output,
                "dateUpload",
                getter(chapter, "getDate_upload"),
                true
            );
            output.append('}');
        }
        output.append("]}");
        return output.toString();
    }

    private static void appendManga(StringBuilder output, Object manga)
        throws Exception {
        output.append('{');
        appendJsonField(output, "url", getter(manga, "getUrl"), false);
        appendJsonField(output, "title", getter(manga, "getTitle"), true);
        appendJsonField(
            output,
            "thumbnailURL",
            getter(manga, "getThumbnail_url"),
            true
        );
        appendJsonField(output, "artist", getter(manga, "getArtist"), true);
        appendJsonField(output, "author", getter(manga, "getAuthor"), true);
        appendJsonField(output, "status", getter(manga, "getStatus"), true);
        appendJsonField(
            output,
            "description",
            getter(manga, "getDescription"),
            true
        );
        appendJsonField(output, "genre", getter(manga, "getGenre"), true);
        output.append('}');
    }

    @SuppressWarnings("unchecked")
    private static String serializePages(Object source, Object value)
        throws Exception {
        List<Object> pages = (List<Object>) value;
        StringBuilder output = new StringBuilder("[");
        for (int index = 0; index < pages.size(); index++) {
            if (index > 0) {
                output.append(',');
            }
            Object page = pages.get(index);
            Object imageURL = getter(page, "getImageUrl");
            Object pageURL = getter(page, "getUrl");
            if (
                (imageURL == null || imageURL.toString().isEmpty()) &&
                pageURL != null &&
                !pageURL.toString().isEmpty()
            ) {
                try {
                    imageURL = invokeSuspend(
                        source,
                        "getImageUrl",
                        new Class<?>[] { page.getClass() },
                        page
                    );
                } catch (NoSuchMethodException unsupported) {
                    imageURL = null;
                }
            }
            output.append('{');
            appendJsonField(output, "index", getter(page, "getIndex"), false);
            appendJsonField(output, "url", pageURL, true);
            appendJsonField(
                output,
                "imageURL",
                imageURL,
                true
            );
            Object uri = getter(page, "getUri");
            appendJsonField(
                output,
                "uri",
                uri == null ? null : uri.toString(),
                true
            );
            output.append('}');
        }
        output.append(']');
        return output.toString();
    }

    private static Object getter(Object instance, String name)
        throws Exception {
        return instance.getClass().getMethod(name).invoke(instance);
    }

    private static void setter(
        Object instance,
        String name,
        Class<?> parameterType,
        Object value
    ) throws Exception {
        instance.getClass().getMethod(name, parameterType)
            .invoke(instance, value);
    }

    private static String defaultValue(String value, String fallback) {
        return value == null ? fallback : value;
    }

    private static void appendJsonField(
        StringBuilder output,
        String key,
        Object value,
        boolean comma
    ) {
        if (comma) {
            output.append(',');
        }
        output.append('"')
            .append(MiniJson.escapeValue(key))
            .append("\":");
        if (value == null) {
            output.append("null");
        } else if (value instanceof Number || value instanceof Boolean) {
            output.append(value);
        } else {
            output.append('"')
                .append(MiniJson.escapeValue(value.toString()))
                .append('"');
        }
    }

    private static String invoke(Map<String, String> request) throws Exception {
        String extensionId = require(request, "extensionId");
        String methodName = require(request, "method");
        String argument = request.get("argument");
        LoadedExtension extension = EXTENSIONS.get(extensionId);
        if (extension == null) {
            throw new IllegalArgumentException(
                "Extension is not loaded: " + extensionId
            );
        }

        Object target = extension.source(request.get("sourceId"));
        Method method;
        Object value;
        if (argument == null) {
            method = target.getClass().getMethod(methodName);
            value = method.invoke(target);
        } else {
            method = target
                .getClass()
                .getMethod(methodName, String.class);
            value = method.invoke(target, argument);
        }
        return MiniJson.response(
            true,
            value == null ? null : value.toString(),
            null,
            null
        );
    }

    private static String unloadExtension(Map<String, String> request)
        throws Exception {
        String extensionId = require(request, "extensionId");
        LoadedExtension extension = EXTENSIONS.remove(extensionId);
        if (extension != null) {
            extension.close();
        }
        return MiniJson.response(true, extensionId, null, null);
    }

    private static String decodeBackup(Map<String, String> request)
        throws Exception {
        File backup = new File(require(request, "backupPath"));
        return MiniJson.response(
            true,
            MihonBackupDecoder.decodeToJson(backup),
            null,
            null
        );
    }

    private static String require(Map<String, String> request, String key) {
        String value = request.get(key);
        if (value == null || value.isEmpty()) {
            throw new IllegalArgumentException("Missing field: " + key);
        }
        return value;
    }

    private static Map<String, String> metadataMap(
        KeiyoushiJarMetadata.Metadata metadata
    ) {
        Map<String, String> response = new LinkedHashMap<>();
        response.put("packageName", metadata.packageName);
        response.put("name", metadata.name);
        response.put("version", metadata.version);
        response.put("versionCode", metadata.versionCode);
        response.put("entryClass", metadata.entryClass);
        response.put("minimumSdk", metadata.minimumSdk);
        response.put("targetSdk", metadata.targetSdk);
        response.put("nsfw", metadata.nsfw);
        response.put("extensionLibrary", metadata.extensionLibrary);
        response.put(
            "classCount",
            Integer.toString(metadata.bytecode.classCount)
        );
        response.put(
            "maximumClassVersion",
            Integer.toString(metadata.bytecode.maximumMajorVersion)
        );
        response.put(
            "requiredJavaVersion",
            Integer.toString(
                JarBytecodeValidator.javaVersionForClassVersion(
                    metadata.bytecode.maximumMajorVersion
                )
            )
        );
        response.put(
            "runtimeCompatible",
            Boolean.toString(
                metadata.bytecode.isCompatibleWithCurrentRuntime()
            )
        );
        return response;
    }

    private static String describe(Throwable error) {
        Throwable cause = error;
        while (cause.getCause() != null && cause.getCause() != cause) {
            cause = cause.getCause();
        }
        String message = cause.getMessage();
        return cause.getClass().getName() +
            (message == null ? "" : ": " + message);
    }

    private static final class LoadedExtension {
        final URLClassLoader loader;
        final Object entry;
        final List<Object> sources;
        final Object defaultSource;

        LoadedExtension(
            URLClassLoader loader,
            Object entry,
            List<Object> sources
        ) throws Exception {
            this.loader = loader;
            this.entry = entry;
            this.sources = sources;
            Object fallback = sources.get(0);
            for (Object source : sources) {
                try {
                    Object lang = getter(source, "getLang");
                    if ("en".equals(lang)) {
                        fallback = source;
                        break;
                    }
                } catch (NoSuchMethodException notASource) {
                    // Host-only fixtures may expose arbitrary entry objects.
                }
            }
            defaultSource = fallback;
        }

        Object source(String sourceId) throws Exception {
            if (sourceId == null || sourceId.isEmpty()) {
                return defaultSource;
            }
            for (Object source : sources) {
                if (
                    sourceId.equals(
                        getter(source, "getId").toString()
                    )
                ) {
                    return source;
                }
            }
            throw new IllegalArgumentException(
                "Source is not loaded: " + sourceId
            );
        }

        void close() throws Exception {
            loader.close();
        }
    }
}
