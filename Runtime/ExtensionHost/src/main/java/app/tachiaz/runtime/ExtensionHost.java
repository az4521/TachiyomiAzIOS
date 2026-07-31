package app.tachiaz.runtime;

import java.io.File;
import java.lang.reflect.Array;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.net.URL;
import java.net.URLClassLoader;
import java.util.List;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public final class ExtensionHost {
    private static final ConcurrentHashMap<String, LoadedExtension> EXTENSIONS =
        new ConcurrentHashMap<>();
    private static boolean compatibilityInitialized;

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
        try {
            Class<?> type = Class.forName(entryClass, true, loader);
            instance = type.getDeclaredConstructor().newInstance();
        } catch (Throwable error) {
            loader.close();
            throw error;
        }

        LoadedExtension replacement = new LoadedExtension(loader, instance);
        LoadedExtension previous = EXTENSIONS.put(extensionId, replacement);
        if (previous != null) {
            previous.close();
        }
        return MiniJson.response(true, entryClass, null, null);
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
            extension.instance,
            "getPopularManga",
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
            appendJsonField(
                output,
                "status",
                getter(manga, "getStatus"),
                true
            );
            appendJsonField(
                output,
                "description",
                getter(manga, "getDescription"),
                true
            );
            appendJsonField(output, "genre", getter(manga, "getGenre"), true);
            output.append('}');
        }
        output.append("],\"hasNextPage\":")
            .append(hasNextPage)
            .append('}');
        return output.toString();
    }

    private static Object getter(Object instance, String name)
        throws Exception {
        return instance.getClass().getMethod(name).invoke(instance);
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

        Method method;
        Object value;
        if (argument == null) {
            method = extension.instance.getClass().getMethod(methodName);
            value = method.invoke(extension.instance);
        } else {
            method = extension.instance
                .getClass()
                .getMethod(methodName, String.class);
            value = method.invoke(extension.instance, argument);
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
        final Object instance;

        LoadedExtension(URLClassLoader loader, Object instance) {
            this.loader = loader;
            this.instance = instance;
        }

        void close() throws Exception {
            loader.close();
        }
    }
}
