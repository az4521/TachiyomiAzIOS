package app.tachiaz.runtime;

import java.io.File;
import java.lang.reflect.Method;
import java.net.URL;
import java.net.URLClassLoader;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

public final class ExtensionHost {
    private static final ConcurrentHashMap<String, LoadedExtension> EXTENSIONS =
        new ConcurrentHashMap<>();

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
                case "loadExtension":
                    return loadExtension(request);
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
        metadata.put("runtime", "OpenJDK Zero");
        metadata.put("javaVersion", System.getProperty("java.version"));
        return MiniJson.response(true, "pong", null, metadata);
    }

    private static String loadExtension(Map<String, String> request)
        throws Exception {
        String extensionId = require(request, "extensionId");
        File jar = new File(require(request, "jarPath"));
        String entryClass = require(request, "entryClass");

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

        Method method = extension.instance
            .getClass()
            .getMethod(methodName, String.class);
        Object value = method.invoke(extension.instance, argument);
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
