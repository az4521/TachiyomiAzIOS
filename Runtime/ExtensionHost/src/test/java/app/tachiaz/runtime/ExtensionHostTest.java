package app.tachiaz.runtime;

import android.net.Uri;
import android.util.Base64;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.zip.GZIPOutputStream;

public final class ExtensionHostTest {
    private ExtensionHostTest() {
    }

    public static void main(String[] arguments) throws Exception {
        if (arguments.length != 1) {
            throw new AssertionError("Expected the fixture JAR path");
        }

        String ping = ExtensionHost.dispatch("{\"operation\":\"ping\"}");
        assertContains(ping, "\"result\":\"pong\"");
        assertEquals("true", MiniJson.parseObject(ping).get("success"));
        assertEquals("pong", MiniJson.parseObject(ping).get("result"));
        assertEquals(
            "https://example.test/manga/one?q=hello%20world",
            Uri.parse("https://example.test")
                .buildUpon()
                .appendPath("manga")
                .appendPath("one")
                .appendQueryParameter("q", "hello world")
                .build()
                .toString()
        );
        assertEquals(
            "aGVsbG8",
            Base64.encodeToString(
                "hello".getBytes(StandardCharsets.UTF_8),
                Base64.NO_WRAP | Base64.NO_PADDING
            )
        );

        String escapedPath = arguments[0]
            .replace("\\", "\\\\")
            .replace("\"", "\\\"");
        assertContains(
            ExtensionHost.dispatch(
                "{\"operation\":\"loadExtension\"," +
                    "\"extensionId\":\"fixture\"," +
                    "\"jarPath\":\"" + escapedPath + "\"," +
                    "\"entryClass\":\"fixture.EchoExtension\"}"
            ),
            "\"success\":true"
        );
        assertContains(
            ExtensionHost.dispatch(
                "{\"operation\":\"invoke\"," +
                    "\"extensionId\":\"fixture\"," +
                    "\"method\":\"echo\"," +
                    "\"argument\":\"hello\"}"
            ),
            "\"result\":\"echo:hello\""
        );
        assertContains(
            ExtensionHost.dispatch(
                "{\"operation\":\"unloadExtension\"," +
                    "\"extensionId\":\"fixture\"}"
            ),
            "\"success\":true"
        );

        File backup = createBackupFixture();
        String escapedBackupPath = backup.getAbsolutePath()
            .replace("\\", "\\\\")
            .replace("\"", "\\\"");
        String decoded = ExtensionHost.dispatch(
            "{\"operation\":\"decodeBackup\"," +
                "\"backupPath\":\"" + escapedBackupPath + "\"}"
        );
        assertContains(decoded, "\\\"title\\\":\\\"Fixture Manga\\\"");
        assertContains(decoded, "\\\"name\\\":\\\"Chapter 1\\\"");
        assertContains(decoded, "\\\"name\\\":\\\"Reading\\\"");
        assertContains(decoded, "\\\"name\\\":\\\"Fixture Source\\\"");
        if (!backup.delete()) {
            backup.deleteOnExit();
        }

        System.out.println("ExtensionHost tests passed");
    }

    private static File createBackupFixture() throws Exception {
        ByteArrayOutputStream chapter = new ByteArrayOutputStream();
        stringField(chapter, 1, "/chapter-1");
        stringField(chapter, 2, "Chapter 1");
        varintField(chapter, 4, 1);

        ByteArrayOutputStream manga = new ByteArrayOutputStream();
        varintField(manga, 1, 42);
        stringField(manga, 2, "/fixture");
        stringField(manga, 3, "Fixture Manga");
        messageField(manga, 16, chapter.toByteArray());
        varintField(manga, 17, 7);

        ByteArrayOutputStream category = new ByteArrayOutputStream();
        stringField(category, 1, "Reading");
        varintField(category, 2, 0);
        varintField(category, 3, 7);

        ByteArrayOutputStream source = new ByteArrayOutputStream();
        stringField(source, 1, "Fixture Source");
        varintField(source, 2, 42);

        ByteArrayOutputStream root = new ByteArrayOutputStream();
        messageField(root, 1, manga.toByteArray());
        messageField(root, 2, category.toByteArray());
        messageField(root, 101, source.toByteArray());

        File file = File.createTempFile("tachiaz-backup-", ".tachibk");
        try (
            GZIPOutputStream gzip = new GZIPOutputStream(
                new FileOutputStream(file)
            )
        ) {
            gzip.write(root.toByteArray());
        }
        return file;
    }

    private static void stringField(
        ByteArrayOutputStream output,
        int field,
        String value
    ) {
        messageField(
            output,
            field,
            value.getBytes(StandardCharsets.UTF_8)
        );
    }

    private static void messageField(
        ByteArrayOutputStream output,
        int field,
        byte[] value
    ) {
        writeVarint(output, ((long) field << 3) | 2);
        writeVarint(output, value.length);
        output.write(value, 0, value.length);
    }

    private static void varintField(
        ByteArrayOutputStream output,
        int field,
        long value
    ) {
        writeVarint(output, (long) field << 3);
        writeVarint(output, value);
    }

    private static void writeVarint(
        ByteArrayOutputStream output,
        long value
    ) {
        while ((value & ~0x7fL) != 0) {
            output.write((int) (value & 0x7f) | 0x80);
            value >>>= 7;
        }
        output.write((int) value);
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

    private static void assertEquals(String expected, String actual) {
        if (!expected.equals(actual)) {
            throw new AssertionError(
                "Expected " + expected + ", got " + actual
            );
        }
    }
}
