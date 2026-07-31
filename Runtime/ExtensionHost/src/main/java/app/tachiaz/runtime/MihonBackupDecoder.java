package app.tachiaz.runtime;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.zip.GZIPInputStream;

final class MihonBackupDecoder {
    private MihonBackupDecoder() {
    }

    static String decodeToJson(File file) throws IOException {
        if (!file.isFile()) {
            throw new IllegalArgumentException(
                "Backup does not exist: " + file
            );
        }
        byte[] compressed = readAll(new FileInputStream(file));
        InputStream input;
        if (
            compressed.length >= 2 &&
            (compressed[0] & 0xff) == 0x1f &&
            (compressed[1] & 0xff) == 0x8b
        ) {
            input = new GZIPInputStream(new ByteArrayInputStream(compressed));
        } else {
            input = new ByteArrayInputStream(compressed);
        }
        Reader root = new Reader(readAll(input));
        List<Manga> manga = new ArrayList<>();
        List<Category> categories = new ArrayList<>();
        List<Source> sources = new ArrayList<>();
        while (root.hasRemaining()) {
            int tag = root.readTag();
            int field = tag >>> 3;
            if (field == 1) {
                manga.add(readManga(root.readMessage()));
            } else if (field == 2) {
                categories.add(readCategory(root.readMessage()));
            } else if (field == 101) {
                sources.add(readSource(root.readMessage()));
            } else {
                root.skip(tag & 7);
            }
        }
        return toJson(manga, categories, sources);
    }

    private static Manga readManga(Reader reader) throws IOException {
        Manga value = new Manga();
        while (reader.hasRemaining()) {
            int tag = reader.readTag();
            int field = tag >>> 3;
            int wire = tag & 7;
            switch (field) {
                case 1:
                    value.source = reader.readVarint();
                    break;
                case 2:
                    value.url = reader.readString();
                    break;
                case 3:
                    value.title = reader.readString();
                    break;
                case 4:
                    value.artist = reader.readString();
                    break;
                case 5:
                    value.author = reader.readString();
                    break;
                case 6:
                    value.description = reader.readString();
                    break;
                case 7:
                    value.genre.add(reader.readString());
                    break;
                case 8:
                    value.status = (int) reader.readVarint();
                    break;
                case 9:
                    value.thumbnailUrl = reader.readString();
                    break;
                case 13:
                    value.dateAdded = reader.readVarint();
                    break;
                case 14:
                    value.viewer = (int) reader.readVarint();
                    break;
                case 16:
                    value.chapters.add(readChapter(reader.readMessage()));
                    break;
                case 17:
                    if (wire == 2) {
                        Reader packed = reader.readMessage();
                        while (packed.hasRemaining()) {
                            value.categories.add(packed.readVarint());
                        }
                    } else {
                        value.categories.add(reader.readVarint());
                    }
                    break;
                case 100:
                    value.favorite = reader.readVarint() != 0;
                    break;
                case 101:
                    value.chapterFlags = (int) reader.readVarint();
                    break;
                case 103:
                    value.viewerFlags = (int) reader.readVarint();
                    break;
                case 104:
                    value.history.add(readHistory(reader.readMessage()));
                    break;
                case 105:
                    value.updateStrategy = (int) reader.readVarint();
                    break;
                case 108:
                    value.excludedScanlators.add(reader.readString());
                    break;
                case 110:
                    value.notes = reader.readString();
                    break;
                case 111:
                    value.initialized = reader.readVarint() != 0;
                    break;
                default:
                    reader.skip(wire);
            }
        }
        return value;
    }

    private static Chapter readChapter(Reader reader) throws IOException {
        Chapter value = new Chapter();
        while (reader.hasRemaining()) {
            int tag = reader.readTag();
            int field = tag >>> 3;
            int wire = tag & 7;
            switch (field) {
                case 1:
                    value.url = reader.readString();
                    break;
                case 2:
                    value.name = reader.readString();
                    break;
                case 3:
                    value.scanlator = reader.readString();
                    break;
                case 4:
                    value.read = reader.readVarint() != 0;
                    break;
                case 5:
                    value.bookmark = reader.readVarint() != 0;
                    break;
                case 6:
                    value.lastPageRead = reader.readVarint();
                    break;
                case 7:
                    value.dateFetch = reader.readVarint();
                    break;
                case 8:
                    value.dateUpload = reader.readVarint();
                    break;
                case 9:
                    value.chapterNumber = reader.readFloat();
                    break;
                case 10:
                    value.sourceOrder = reader.readVarint();
                    break;
                default:
                    reader.skip(wire);
            }
        }
        return value;
    }

    private static History readHistory(Reader reader) throws IOException {
        History value = new History();
        while (reader.hasRemaining()) {
            int tag = reader.readTag();
            int field = tag >>> 3;
            int wire = tag & 7;
            if (field == 1) {
                value.url = reader.readString();
            } else if (field == 2) {
                value.lastRead = reader.readVarint();
            } else if (field == 3) {
                value.readDuration = reader.readVarint();
            } else {
                reader.skip(wire);
            }
        }
        return value;
    }

    private static Category readCategory(Reader reader) throws IOException {
        Category value = new Category();
        while (reader.hasRemaining()) {
            int tag = reader.readTag();
            int field = tag >>> 3;
            int wire = tag & 7;
            if (field == 1) {
                value.name = reader.readString();
            } else if (field == 2) {
                value.order = reader.readVarint();
            } else if (field == 3) {
                value.id = reader.readVarint();
            } else if (field == 100) {
                value.flags = reader.readVarint();
            } else {
                reader.skip(wire);
            }
        }
        return value;
    }

    private static Source readSource(Reader reader) throws IOException {
        Source value = new Source();
        while (reader.hasRemaining()) {
            int tag = reader.readTag();
            int field = tag >>> 3;
            int wire = tag & 7;
            if (field == 1) {
                value.name = reader.readString();
            } else if (field == 2) {
                value.id = reader.readVarint();
            } else {
                reader.skip(wire);
            }
        }
        return value;
    }

    private static String toJson(
        List<Manga> manga,
        List<Category> categories,
        List<Source> sources
    ) {
        StringBuilder out = new StringBuilder("{\"manga\":[");
        appendList(out, manga);
        out.append("],\"categories\":[");
        appendList(out, categories);
        out.append("],\"sources\":[");
        appendList(out, sources);
        return out.append("]}").toString();
    }

    private static void appendList(StringBuilder out, List<?> values) {
        for (int index = 0; index < values.size(); index++) {
            if (index > 0) {
                out.append(',');
            }
            out.append(values.get(index));
        }
    }

    private static void field(
        StringBuilder out,
        String name,
        String value,
        boolean quoted
    ) {
        if (out.length() > 1 && out.charAt(out.length() - 1) != '{') {
            out.append(',');
        }
        out.append('"').append(name).append("\":");
        if (value == null) {
            out.append("null");
        } else if (quoted) {
            out.append('"').append(MiniJson.escapeValue(value)).append('"');
        } else {
            out.append(value);
        }
    }

    private static void stringList(
        StringBuilder out,
        String name,
        List<String> values
    ) {
        if (out.length() > 1 && out.charAt(out.length() - 1) != '{') {
            out.append(',');
        }
        out.append('"').append(name).append("\":[");
        for (int index = 0; index < values.size(); index++) {
            if (index > 0) {
                out.append(',');
            }
            out.append('"')
                .append(MiniJson.escapeValue(values.get(index)))
                .append('"');
        }
        out.append(']');
    }

    private static void longList(
        StringBuilder out,
        String name,
        List<Long> values
    ) {
        if (out.length() > 1 && out.charAt(out.length() - 1) != '{') {
            out.append(',');
        }
        out.append('"').append(name).append("\":[");
        for (int index = 0; index < values.size(); index++) {
            if (index > 0) {
                out.append(',');
            }
            out.append(values.get(index));
        }
        out.append(']');
    }

    private static byte[] readAll(InputStream input) throws IOException {
        try (InputStream source = input) {
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            int count;
            while ((count = source.read(buffer)) >= 0) {
                output.write(buffer, 0, count);
            }
            return output.toByteArray();
        }
    }

    private static final class Reader {
        final byte[] data;
        int index;

        Reader(byte[] data) {
            this.data = data;
        }

        boolean hasRemaining() {
            return index < data.length;
        }

        int readTag() throws IOException {
            long tag = readVarint();
            if (tag == 0 || tag > Integer.MAX_VALUE) {
                throw new IOException("Invalid protobuf tag");
            }
            return (int) tag;
        }

        long readVarint() throws IOException {
            long value = 0;
            for (int shift = 0; shift < 64; shift += 7) {
                if (index >= data.length) {
                    throw new IOException("Truncated protobuf varint");
                }
                int current = data[index++] & 0xff;
                value |= (long) (current & 0x7f) << shift;
                if ((current & 0x80) == 0) {
                    return value;
                }
            }
            throw new IOException("Invalid protobuf varint");
        }

        String readString() throws IOException {
            return new String(readBytes(), StandardCharsets.UTF_8);
        }

        Reader readMessage() throws IOException {
            return new Reader(readBytes());
        }

        float readFloat() throws IOException {
            require(4);
            int bits =
                (data[index] & 0xff) |
                ((data[index + 1] & 0xff) << 8) |
                ((data[index + 2] & 0xff) << 16) |
                ((data[index + 3] & 0xff) << 24);
            index += 4;
            return Float.intBitsToFloat(bits);
        }

        byte[] readBytes() throws IOException {
            long rawLength = readVarint();
            if (rawLength < 0 || rawLength > Integer.MAX_VALUE) {
                throw new IOException("Invalid protobuf length");
            }
            int length = (int) rawLength;
            require(length);
            byte[] value = new byte[length];
            System.arraycopy(data, index, value, 0, length);
            index += length;
            return value;
        }

        void skip(int wire) throws IOException {
            switch (wire) {
                case 0:
                    readVarint();
                    return;
                case 1:
                    require(8);
                    index += 8;
                    return;
                case 2:
                    int length = (int) readVarint();
                    require(length);
                    index += length;
                    return;
                case 5:
                    require(4);
                    index += 4;
                    return;
                default:
                    throw new IOException(
                        "Unsupported protobuf wire type " + wire
                    );
            }
        }

        private void require(int count) throws IOException {
            if (count < 0 || index + count > data.length) {
                throw new IOException("Truncated protobuf field");
            }
        }
    }

    private static final class Manga {
        long source;
        String url = "";
        String title = "";
        String artist;
        String author;
        String description;
        final List<String> genre = new ArrayList<>();
        int status;
        String thumbnailUrl;
        long dateAdded;
        int viewer;
        final List<Chapter> chapters = new ArrayList<>();
        final List<Long> categories = new ArrayList<>();
        boolean favorite = true;
        int chapterFlags;
        Integer viewerFlags;
        final List<History> history = new ArrayList<>();
        int updateStrategy;
        final List<String> excludedScanlators = new ArrayList<>();
        String notes = "";
        boolean initialized;

        @Override
        public String toString() {
            StringBuilder out = new StringBuilder("{");
            field(out, "source", Long.toString(source), true);
            field(out, "url", url, true);
            field(out, "title", title, true);
            field(out, "artist", artist, true);
            field(out, "author", author, true);
            field(out, "description", description, true);
            stringList(out, "genre", genre);
            field(out, "status", Integer.toString(status), false);
            field(out, "thumbnailUrl", thumbnailUrl, true);
            field(out, "dateAdded", Long.toString(dateAdded), false);
            field(out, "viewer", Integer.toString(viewer), false);
            out.append(",\"chapters\":[");
            appendList(out, chapters);
            out.append(']');
            longList(out, "categories", categories);
            field(out, "favorite", Boolean.toString(favorite), false);
            field(out, "chapterFlags", Integer.toString(chapterFlags), false);
            field(
                out,
                "viewerFlags",
                viewerFlags == null ? null : viewerFlags.toString(),
                false
            );
            out.append(",\"history\":[");
            appendList(out, history);
            out.append(']');
            field(
                out,
                "updateStrategy",
                Integer.toString(updateStrategy),
                false
            );
            stringList(out, "excludedScanlators", excludedScanlators);
            field(out, "notes", notes, true);
            field(out, "initialized", Boolean.toString(initialized), false);
            return out.append('}').toString();
        }
    }

    private static final class Chapter {
        String url = "";
        String name = "";
        String scanlator;
        boolean read;
        boolean bookmark;
        long lastPageRead;
        long dateFetch;
        long dateUpload;
        float chapterNumber;
        long sourceOrder;

        @Override
        public String toString() {
            StringBuilder out = new StringBuilder("{");
            field(out, "url", url, true);
            field(out, "name", name, true);
            field(out, "scanlator", scanlator, true);
            field(out, "read", Boolean.toString(read), false);
            field(out, "bookmark", Boolean.toString(bookmark), false);
            field(out, "lastPageRead", Long.toString(lastPageRead), false);
            field(out, "dateFetch", Long.toString(dateFetch), false);
            field(out, "dateUpload", Long.toString(dateUpload), false);
            field(out, "chapterNumber", Float.toString(chapterNumber), false);
            field(out, "sourceOrder", Long.toString(sourceOrder), false);
            return out.append('}').toString();
        }
    }

    private static final class History {
        String url = "";
        long lastRead;
        long readDuration;

        @Override
        public String toString() {
            StringBuilder out = new StringBuilder("{");
            field(out, "url", url, true);
            field(out, "lastRead", Long.toString(lastRead), false);
            field(out, "readDuration", Long.toString(readDuration), false);
            return out.append('}').toString();
        }
    }

    private static final class Category {
        String name = "";
        long order;
        long id;
        long flags;

        @Override
        public String toString() {
            StringBuilder out = new StringBuilder("{");
            field(out, "name", name, true);
            field(out, "order", Long.toString(order), false);
            field(out, "id", Long.toString(id), false);
            field(out, "flags", Long.toString(flags), false);
            return out.append('}').toString();
        }
    }

    private static final class Source {
        String name = "";
        long id;

        @Override
        public String toString() {
            StringBuilder out = new StringBuilder("{");
            field(out, "name", name, true);
            field(out, "id", Long.toString(id), true);
            return out.append('}').toString();
        }
    }
}
