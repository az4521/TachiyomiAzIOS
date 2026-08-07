package app.tachiaz.compat;

/** Native iOS implementations used by the Android compatibility surface. */
public final class NativeBridge {
    private NativeBridge() {
    }

    public static native long[] bitmapCreate(int width, int height);
    public static native long[] bitmapDecode(byte[] data, int offset, int length);
    public static native long[] bitmapCrop(
        long handle,
        int x,
        int y,
        int width,
        int height
    );
    public static native void bitmapRelease(long handle);
    public static native byte[] bitmapCompress(
        long handle,
        int format,
        int quality
    );
    public static native void bitmapErase(long handle, int color);
    public static native int bitmapGetPixel(long handle, int x, int y);
    public static native void bitmapSetPixel(
        long handle,
        int x,
        int y,
        int color
    );
    public static native void bitmapGetPixels(
        long handle,
        int[] pixels,
        int offset,
        int stride,
        int x,
        int y,
        int width,
        int height
    );
    public static native void bitmapSetPixels(
        long handle,
        int[] pixels,
        int offset,
        int stride,
        int x,
        int y,
        int width,
        int height
    );
    public static native void canvasDrawBitmap(
        long destination,
        long source,
        int sourceLeft,
        int sourceTop,
        int sourceRight,
        int sourceBottom,
        int destinationLeft,
        int destinationTop,
        int destinationRight,
        int destinationBottom
    );
    public static native void canvasDrawText(
        long handle,
        String text,
        float x,
        float baseline,
        float size,
        int color,
        boolean bold
    );
    public static native float[] textFontMetrics(float size, boolean bold);
    public static native int[] textLineEnds(
        String text,
        float width,
        float size,
        boolean bold
    );

    public static native long javascriptCreate();
    public static native Object javascriptEvaluate(long handle, String script);
    public static native void javascriptClose(long handle);
}
