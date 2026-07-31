package app.tachiaz.runtime;

import java.io.File;
import java.util.ArrayList;
import java.util.List;

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
        assertContains(sources, "\\\"supportsLatest\\\":true");

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

        String latest = ExtensionHost.dispatch(
            "{\"operation\":\"getLatestUpdates\"," +
                "\"extensionId\":\"mangadex\"," +
                "\"sourceId\":\"" + ENGLISH_SOURCE_ID + "\"," +
                "\"argument\":\"1\"}"
        );
        assertSuccess(latest);
        assertContains(latest, "\\\"mangas\\\":[{");

        String search = ExtensionHost.dispatch(
            "{\"operation\":\"searchManga\"," +
                "\"extensionId\":\"mangadex\"," +
                "\"sourceId\":\"" + ENGLISH_SOURCE_ID + "\"," +
                "\"query\":\"One Piece\"," +
                "\"argument\":\"1\"}"
        );
        assertSuccess(search);
        assertContains(search, "\\\"mangas\\\":[{");
        assertContains(search, "\\\"title\\\":");

        String latestResult = MiniJson.parseObject(latest).get("result");
        String mangaURL = firstStringField(latestResult, "url");
        String mangaTitle = firstStringField(latestResult, "title");
        String update = ExtensionHost.dispatch(
            "{\"operation\":\"getMangaUpdate\"," +
                "\"extensionId\":\"mangadex\"," +
                "\"sourceId\":\"" + ENGLISH_SOURCE_ID + "\"," +
                "\"mangaURL\":\"" +
                MiniJson.escapeValue(mangaURL) +
                "\",\"mangaTitle\":\"" +
                MiniJson.escapeValue(mangaTitle) +
                "\"}"
        );
        assertSuccess(update);
        assertContains(update, "\\\"manga\\\":{");
        assertContains(update, "\\\"chapters\\\":[{");

        String updateResult = MiniJson.parseObject(update).get("result");
        String chaptersJson = updateResult.substring(
            updateResult.indexOf("\"chapters\":")
        );
        List<String> chapterURLs = stringFields(chaptersJson, "url");
        String pages = null;
        for (
            int index = 0;
            index < chapterURLs.size() && index < 20;
            index++
        ) {
            String candidate = ExtensionHost.dispatch(
                "{\"operation\":\"getPageList\"," +
                    "\"extensionId\":\"mangadex\"," +
                    "\"sourceId\":\"" + ENGLISH_SOURCE_ID + "\"," +
                    "\"chapterURL\":\"" +
                    MiniJson.escapeValue(chapterURLs.get(index)) +
                    "\",\"chapterName\":\"\"}"
            );
            if (candidate.contains("\"success\":true")) {
                pages = candidate;
                break;
            }
        }
        if (pages == null) {
            throw new AssertionError(
                "No readable chapter found in the first 20 chapters"
            );
        }
        assertContains(pages, "\\\"index\\\":");
        assertContains(pages, "\\\"imageURL\\\":");
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

    private static String firstStringField(String json, String field) {
        List<String> values = stringFields(json, field);
        if (values.isEmpty()) {
            throw new AssertionError(
                "Unable to find " + field + " in " + json
            );
        }
        return values.get(0);
    }

    private static List<String> stringFields(String json, String field) {
        String prefix = "\"" + field + "\":\"";
        List<String> values = new ArrayList<>();
        int searchStart = 0;
        while (true) {
            int start = json.indexOf(prefix, searchStart);
            if (start < 0) {
                return values;
            }
            start += prefix.length();
            StringBuilder value = new StringBuilder();
            boolean escaped = false;
            for (int index = start; index < json.length(); index++) {
                char character = json.charAt(index);
                if (escaped) {
                    value.append(character);
                    escaped = false;
                } else if (character == '\\') {
                    escaped = true;
                } else if (character == '"') {
                    values.add(value.toString());
                    searchStart = index + 1;
                    break;
                } else {
                    value.append(character);
                }
                if (index == json.length() - 1) {
                    throw new AssertionError(
                        "Unterminated " + field + " in " + json
                    );
                }
            }
        }
    }
}
