package app.tachiaz.runtime;

import java.io.File;

public final class KeiyoushiAsuraRuntimeTest {
    private KeiyoushiAsuraRuntimeTest() {
    }

    public static void main(String[] arguments) {
        if (arguments.length != 1) {
            throw new AssertionError("Expected the Asura Scans JAR path");
        }

        String escapedPath = new File(arguments[0])
            .getAbsolutePath()
            .replace("\\", "\\\\")
            .replace("\"", "\\\"");
        assertSuccess(ExtensionHost.dispatch(
            "{\"operation\":\"initializeCompatibility\"}"
        ));
        assertSuccess(ExtensionHost.dispatch(
            "{\"operation\":\"loadExtension\",\"extensionId\":\"asura\"," +
                "\"jarPath\":\"" + escapedPath + "\"}"
        ));

        String response = ExtensionHost.dispatch(
            "{\"operation\":\"getPopularManga\"," +
                "\"extensionId\":\"asura\",\"argument\":\"1\"}"
        );
        assertSuccess(response);
        assertContains(response, "\\\"mangas\\\":[{");
        assertContains(response, "\\\"title\\\":");
        assertContains(response, "\\\"thumbnailURL\\\":");
        assertContains(response, "\\\"hasNextPage\\\":");
        System.out.println("Keiyoushi Asura Scans runtime test passed");

        // OkHttp and coroutine pools are deliberately process-wide in the app.
        // End this short-lived command line test without waiting for them.
        System.exit(0);
    }

    private static void assertSuccess(String response) {
        assertContains(response, "\"success\":true");
    }

    private static void assertContains(String actual, String expected) {
        if (!actual.contains(expected)) {
            throw new AssertionError(
                "Expected response to contain " +
                    expected +
                    ", got " +
                    actual
            );
        }
    }
}
