package app.tachiaz.runtime;

import java.io.File;

public final class KeiyoushiMangaDexRuntimeTest {
    private static final String ENGLISH_SOURCE_ID = "2499283573021220255";

    private KeiyoushiMangaDexRuntimeTest() {
    }

    public static void main(String[] arguments) {
        if (arguments.length != 1) {
            throw new AssertionError("Expected the MangaDex JAR path");
        }

        String escapedPath = new File(arguments[0])
            .getAbsolutePath()
            .replace("\\", "\\\\")
            .replace("\"", "\\\"");
        String inspection = ExtensionHost.dispatch(
            "{\"operation\":\"inspectExtension\"," +
                "\"jarPath\":\"" + escapedPath + "\"}"
        );
        assertSuccess(inspection);
        assertContains(inspection, "\"name\":\"MangaDex\"");
        assertContains(inspection, "\"extensionLibrary\":\"1.4\"");

        assertSuccess(ExtensionHost.dispatch(
            "{\"operation\":\"initializeCompatibility\"}"
        ));
        String loaded = ExtensionHost.dispatch(
            "{\"operation\":\"loadExtension\",\"extensionId\":\"mangadex\"," +
                "\"jarPath\":\"" + escapedPath + "\"}"
        );
        assertSuccess(loaded);
        assertContains(loaded, "\"sourceCount\":\"61\"");

        String sources = ExtensionHost.dispatch(
            "{\"operation\":\"listSources\",\"extensionId\":\"mangadex\"}"
        );
        assertSuccess(sources);
        assertContains(sources, "\\\"id\\\":" + ENGLISH_SOURCE_ID);
        assertContains(sources, "\\\"lang\\\":\\\"en\\\"");

        String popular = ExtensionHost.dispatch(
            "{\"operation\":\"getPopularManga\"," +
                "\"extensionId\":\"mangadex\"," +
                "\"sourceId\":\"" + ENGLISH_SOURCE_ID + "\"," +
                "\"argument\":\"1\"}"
        );
        assertSuccess(popular);
        assertContains(popular, "\\\"mangas\\\":[{");
        assertContains(popular, "\\\"title\\\":");
        assertContains(popular, "\\\"hasNextPage\\\":");
        System.out.println(
            "Keiyoushi MangaDex extension-lib 1.4 runtime test passed"
        );
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
