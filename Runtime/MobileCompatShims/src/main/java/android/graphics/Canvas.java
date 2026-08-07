package android.graphics;

import app.tachiaz.compat.NativeBridge;
import java.util.ArrayList;
import java.util.List;

public final class Canvas {
    private final Bitmap bitmap;
    private float translateX;
    private float translateY;
    private final List<float[]> states = new ArrayList<float[]>();

    public Canvas(Bitmap bitmap) {
        if (bitmap == null) {
            throw new NullPointerException("bitmap");
        }
        this.bitmap = bitmap;
    }

    public void drawBitmap(Bitmap source, Rect src, Rect dst, Paint paint) {
        if (source == null || src == null || dst == null) {
            throw new NullPointerException();
        }
        NativeBridge.canvasDrawBitmap(
            bitmap.nativeHandle(),
            source.nativeHandle(),
            src.left,
            src.top,
            src.right,
            src.bottom,
            Math.round(dst.left + translateX),
            Math.round(dst.top + translateY),
            Math.round(dst.right + translateX),
            Math.round(dst.bottom + translateY)
        );
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
            x + translateX,
            y + translateY,
            paint.getTextSize(),
            paint.getColor(),
            paint.getTypeface().isBold()
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

    public void translate(float dx, float dy) {
        translateX += dx;
        translateY += dy;
    }

    public void scale(float sx, float sy) {
        // Region-copy users do not require a persistent scale transform.
    }

    public void scale(float sx, float sy, float px, float py) {
        // Region-copy users do not require a persistent scale transform.
    }

    public void rotate(float degrees) {
        // Rotation is intentionally left neutral until an extension requests it.
    }

    public void rotate(float degrees, float px, float py) {
        // Rotation is intentionally left neutral until an extension requests it.
    }

    public int save() {
        states.add(new float[] {translateX, translateY});
        return states.size();
    }

    public void restore() {
        restoreToCount(states.size());
    }

    public void restoreToCount(int saveCount) {
        if (saveCount < 1 || saveCount > states.size()) {
            throw new IllegalArgumentException("invalid save count");
        }
        float[] state = states.get(saveCount - 1);
        translateX = state[0];
        translateY = state[1];
        while (states.size() >= saveCount) {
            states.remove(states.size() - 1);
        }
    }

    public int getSaveCount() {
        return states.size();
    }

    public boolean getClipBounds(Rect bounds) {
        if (bounds == null) {
            throw new NullPointerException("bounds");
        }
        bounds.set(0, 0, bitmap.getWidth(), bitmap.getHeight());
        return true;
    }
}
