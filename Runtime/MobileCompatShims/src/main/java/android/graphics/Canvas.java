package android.graphics;

import app.tachiaz.compat.NativeBridge;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.util.ArrayList;
import java.util.List;
import java.util.zip.CRC32;

public final class Canvas {
    private static final ThreadLocal<Diagnostics> DIAGNOSTICS =
        new ThreadLocal<Diagnostics>();
    private final Bitmap bitmap;
    // Android's affine matrix layout: x' = a*x + c*y + tx,
    // y' = b*x + d*y + ty.
    private float a = 1;
    private float b;
    private float c;
    private float d = 1;
    private float tx;
    private float ty;
    private final List<float[]> states = new ArrayList<float[]>();

    public Canvas(Bitmap bitmap) {
        if (bitmap == null) {
            throw new NullPointerException("bitmap");
        }
        this.bitmap = bitmap;
    }

    public static void beginDiagnostics(String tracePath) {
        if (tracePath == null || tracePath.isEmpty()) {
            DIAGNOSTICS.remove();
            return;
        }
        Diagnostics diagnostics = new Diagnostics(tracePath);
        DIAGNOSTICS.set(diagnostics);
        try {
            Files.deleteIfExists(diagnostics.tracePath);
            Files.deleteIfExists(diagnostics.decodedPath);
        } catch (Exception ignored) {
            // Diagnostics must never make an extension image request fail.
        }
    }

    public static void endDiagnostics() {
        DIAGNOSTICS.remove();
    }

    public void drawBitmap(Bitmap source, Rect src, Rect dst, Paint paint) {
        if (source == null || dst == null) {
            throw new NullPointerException();
        }
        if (src == null) {
            src = new Rect(0, 0, source.getWidth(), source.getHeight());
        }
        int sourceWidth = src.right - src.left;
        int sourceHeight = src.bottom - src.top;
        int destinationWidth = dst.right - dst.left;
        int destinationHeight = dst.bottom - dst.top;
        captureDecodedBitmap(source);
        // Exact, untransformed rectangle copies are common in image
        // descramblers. Pack the coordinates into one array so the iOS Zero
        // JVM never has to marshal trailing rectangle arguments through its
        // native-call stack. That path can corrupt coordinates on arm64.
        if (
            a == 1f && b == 0f && c == 0f && d == 1f &&
            tx == 0f && ty == 0f &&
            sourceWidth > 0 && sourceHeight > 0 &&
            sourceWidth == destinationWidth &&
            sourceHeight == destinationHeight &&
            src.left >= 0 && src.top >= 0 &&
            src.right <= source.getWidth() &&
            src.bottom <= source.getHeight() &&
            dst.left >= 0 && dst.top >= 0 &&
            dst.right <= bitmap.getWidth() &&
            dst.bottom <= bitmap.getHeight() &&
            (long) sourceWidth * sourceHeight <= Integer.MAX_VALUE
        ) {
            NativeBridge.bitmapCopyPixels(
                bitmap.nativeHandle(),
                source.nativeHandle(),
                new int[] {
                    src.left,
                    src.top,
                    src.right,
                    src.bottom,
                    dst.left,
                    dst.top,
                    dst.right,
                    dst.bottom
                }
            );
            traceBitmapCopy(source, bitmap, src, dst, true);
            return;
        }
        NativeBridge.canvasDrawBitmap(
            bitmap.nativeHandle(),
            source.nativeHandle(),
            new int[] {
                src.left,
                src.top,
                src.right,
                src.bottom,
                dst.left,
                dst.top,
                dst.right,
                dst.bottom
            },
            new float[] {a, b, c, d, tx, ty}
        );
        traceBitmapCopy(source, bitmap, src, dst, false);
    }

    private static void captureDecodedBitmap(Bitmap source) {
        Diagnostics diagnostics = DIAGNOSTICS.get();
        if (diagnostics == null || diagnostics.decodedWritten) {
            return;
        }
        diagnostics.decodedWritten = true;
        try (OutputStream output = Files.newOutputStream(
            diagnostics.decodedPath,
            StandardOpenOption.CREATE,
            StandardOpenOption.TRUNCATE_EXISTING
        )) {
            source.compress(Bitmap.CompressFormat.PNG, 100, output);
        } catch (Exception ignored) {
            // Diagnostics must never make an extension image request fail.
        }
    }

    private static void traceBitmapCopy(
        Bitmap sourceBitmap,
        Bitmap destinationBitmap,
        Rect source,
        Rect destination,
        boolean exact
    ) {
        Diagnostics diagnostics = DIAGNOSTICS.get();
        if (diagnostics == null) {
            return;
        }
        String line = source.left + "," + source.top + "," +
            source.right + "," + source.bottom + " -> " +
            destination.left + "," + destination.top + "," +
            destination.right + "," + destination.bottom +
            " | exact=" + exact +
            " sourceCrc=" + bitmapCrc(sourceBitmap, source) +
            " destinationCrc=" + bitmapCrc(destinationBitmap, destination) +
            "\n";
        try {
            Files.write(
                diagnostics.tracePath,
                line.getBytes(StandardCharsets.UTF_8),
                StandardOpenOption.CREATE,
                StandardOpenOption.APPEND
            );
        } catch (Exception ignored) {
            // Diagnostics must never make an extension image request fail.
        }
    }

    private static String bitmapCrc(Bitmap bitmap, Rect rectangle) {
        int width = rectangle.right - rectangle.left;
        int height = rectangle.bottom - rectangle.top;
        if (
            width <= 0 || height <= 0 ||
            (long) width * height > Integer.MAX_VALUE
        ) {
            return "invalid";
        }
        try {
            int[] pixels = new int[width * height];
            bitmap.getPixels(
                pixels,
                0,
                width,
                rectangle.left,
                rectangle.top,
                width,
                height
            );
            CRC32 crc = new CRC32();
            for (int color : pixels) {
                crc.update((color >>> 24) & 0xff);
                crc.update((color >>> 16) & 0xff);
                crc.update((color >>> 8) & 0xff);
                crc.update(color & 0xff);
            }
            return Long.toHexString(crc.getValue());
        } catch (Exception error) {
            return "error";
        }
    }

    private static final class Diagnostics {
        final Path tracePath;
        final Path decodedPath;
        boolean decodedWritten;

        Diagnostics(String tracePath) {
            this.tracePath = Paths.get(tracePath);
            this.decodedPath = Paths.get(tracePath + ".decoded.png");
        }
    }

    public void drawBitmap(Bitmap source, float left, float top, Paint paint) {
        drawBitmap(
            source,
            new Rect(0, 0, source.getWidth(), source.getHeight()),
            new Rect(
                Math.round(left),
                Math.round(top),
                Math.round(left) + source.getWidth(),
                Math.round(top) + source.getHeight()
            ),
            paint
        );
    }

    public void drawText(String text, float x, float y, Paint paint) {
        if (text == null || paint == null) {
            throw new NullPointerException();
        }
        NativeBridge.canvasDrawText(
            bitmap.nativeHandle(),
            text,
            new int[] {
                paint.getColor(),
                paint.getTypeface().isBold() ? 1 : 0,
                paint.getStyle().ordinal()
            },
            paint.getTypeface().getNativeName(),
            new float[] {
                x,
                y,
                paint.getTextSize(),
                paint.getStrokeWidth(),
                a,
                b,
                c,
                d,
                tx,
                ty
            }
        );
    }

    public void drawText(
        String text,
        int start,
        int end,
        float x,
        float y,
        Paint paint
    ) {
        drawText(text.substring(start, end), x, y, paint);
    }

    public void drawText(
        CharSequence text,
        int start,
        int end,
        float x,
        float y,
        Paint paint
    ) {
        drawText(text.subSequence(start, end).toString(), x, y, paint);
    }

    public void drawText(
        char[] text,
        int index,
        int count,
        float x,
        float y,
        Paint paint
    ) {
        drawText(new String(text, index, count), x, y, paint);
    }

    public void drawColor(int color) {
        NativeBridge.bitmapErase(bitmap.nativeHandle(), color);
    }

    public void drawColor(long color) {
        drawColor(Color.toArgb(color));
    }

    public void drawARGB(int alpha, int red, int green, int blue) {
        drawColor(Color.argb(alpha, red, green, blue));
    }

    public void drawRGB(int red, int green, int blue) {
        drawColor(Color.rgb(red, green, blue));
    }

    public int getWidth() {
        return bitmap.getWidth();
    }

    public int getHeight() {
        return bitmap.getHeight();
    }

    public void translate(float dx, float dy) {
        concat(1, 0, 0, 1, dx, dy);
    }

    public void scale(float sx, float sy) {
        concat(sx, 0, 0, sy, 0, 0);
    }

    public void scale(float sx, float sy, float px, float py) {
        translate(px, py);
        scale(sx, sy);
        translate(-px, -py);
    }

    public void rotate(float degrees) {
        double radians = Math.toRadians(degrees);
        float cosine = (float) Math.cos(radians);
        float sine = (float) Math.sin(radians);
        concat(cosine, sine, -sine, cosine, 0, 0);
    }

    public void rotate(float degrees, float px, float py) {
        translate(px, py);
        rotate(degrees);
        translate(-px, -py);
    }

    public void skew(float sx, float sy) {
        concat(1, sy, sx, 1, 0, 0);
    }

    public int save() {
        int saveCount = getSaveCount();
        states.add(new float[] {a, b, c, d, tx, ty});
        return saveCount;
    }

    public void restore() {
        if (states.isEmpty()) {
            throw new IllegalStateException("underflow in restore");
        }
        restoreState(states.remove(states.size() - 1));
    }

    public void restoreToCount(int saveCount) {
        if (saveCount < 1 || saveCount > getSaveCount()) {
            throw new IllegalArgumentException("invalid save count");
        }
        while (getSaveCount() > saveCount) {
            restore();
        }
    }

    public int getSaveCount() {
        return states.size() + 1;
    }

    public boolean getClipBounds(Rect bounds) {
        if (bounds == null) {
            throw new NullPointerException("bounds");
        }
        float determinant = (a * d) - (b * c);
        if (Math.abs(determinant) < 1.0e-8f) {
            bounds.set(0, 0, 0, 0);
            return false;
        }
        float[] corners = new float[] {
            inverseX(0, 0, determinant),
            inverseY(0, 0, determinant),
            inverseX(bitmap.getWidth(), 0, determinant),
            inverseY(bitmap.getWidth(), 0, determinant),
            inverseX(0, bitmap.getHeight(), determinant),
            inverseY(0, bitmap.getHeight(), determinant),
            inverseX(bitmap.getWidth(), bitmap.getHeight(), determinant),
            inverseY(bitmap.getWidth(), bitmap.getHeight(), determinant),
        };
        float left = corners[0];
        float top = corners[1];
        float right = corners[0];
        float bottom = corners[1];
        for (int index = 2; index < corners.length; index += 2) {
            left = Math.min(left, corners[index]);
            top = Math.min(top, corners[index + 1]);
            right = Math.max(right, corners[index]);
            bottom = Math.max(bottom, corners[index + 1]);
        }
        bounds.set(
            (int) Math.floor(left),
            (int) Math.floor(top),
            (int) Math.ceil(right),
            (int) Math.ceil(bottom)
        );
        return true;
    }

    private float inverseX(float x, float y, float determinant) {
        return ((d * (x - tx)) - (c * (y - ty))) / determinant;
    }

    private float inverseY(float x, float y, float determinant) {
        return ((a * (y - ty)) - (b * (x - tx))) / determinant;
    }

    private void concat(
        float otherA,
        float otherB,
        float otherC,
        float otherD,
        float otherTx,
        float otherTy
    ) {
        float nextA = (a * otherA) + (c * otherB);
        float nextB = (b * otherA) + (d * otherB);
        float nextC = (a * otherC) + (c * otherD);
        float nextD = (b * otherC) + (d * otherD);
        float nextTx = (a * otherTx) + (c * otherTy) + tx;
        float nextTy = (b * otherTx) + (d * otherTy) + ty;
        a = nextA;
        b = nextB;
        c = nextC;
        d = nextD;
        tx = nextTx;
        ty = nextTy;
    }

    private void restoreState(float[] state) {
        a = state[0];
        b = state[1];
        c = state[2];
        d = state[3];
        tx = state[4];
        ty = state[5];
    }
}
