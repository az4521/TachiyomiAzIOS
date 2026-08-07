package app.tachiaz.runtime;

import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import javax.crypto.Cipher;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/** Verifies the Android API descriptors used by Tachiyomi extension libraries. */
public final class AndroidCompatibilitySurfaceTest {
    private AndroidCompatibilitySurfaceTest() {
    }

    public static void main(String[] arguments) throws Exception {
        Class<?> bitmap = Class.forName("android.graphics.Bitmap");
        Class<?> bitmapConfig = Class.forName("android.graphics.Bitmap$Config");
        Class<?> bitmapFormat = Class.forName(
            "android.graphics.Bitmap$CompressFormat"
        );
        Class<?> bitmapFactory = Class.forName("android.graphics.BitmapFactory");
        Class<?> bitmapOptions = Class.forName(
            "android.graphics.BitmapFactory$Options"
        );
        Class<?> canvas = Class.forName("android.graphics.Canvas");
        Class<?> paint = Class.forName("android.graphics.Paint");
        Class<?> rect = Class.forName("android.graphics.Rect");
        Class<?> textPaint = Class.forName("android.text.TextPaint");
        Class<?> alignment = Class.forName("android.text.Layout$Alignment");
        Class<?> staticLayout = Class.forName("android.text.StaticLayout");

        bitmap.getMethod("createBitmap", int.class, int.class, bitmapConfig);
        bitmap.getMethod(
            "createBitmap",
            bitmap,
            int.class,
            int.class,
            int.class,
            int.class
        );
        bitmap.getMethod(
            "compress",
            bitmapFormat,
            int.class,
            OutputStream.class
        );
        bitmap.getMethod(
            "setPixels",
            int[].class,
            int.class,
            int.class,
            int.class,
            int.class,
            int.class,
            int.class
        );
        bitmapFactory.getMethod(
            "decodeByteArray",
            byte[].class,
            int.class,
            int.class,
            bitmapOptions
        );
        bitmapFactory.getMethod("decodeStream", InputStream.class);
        canvas.getConstructor(bitmap);
        canvas.getMethod("drawBitmap", bitmap, rect, rect, paint);
        staticLayout.getConstructor(
            CharSequence.class,
            textPaint,
            int.class,
            alignment,
            float.class,
            float.class,
            boolean.class
        );
        Class.forName("android.text.Html").getMethod(
            "fromHtml",
            String.class,
            int.class
        );

        Class<?> decoder = Class.forName("tachiyomi.decoder.ImageDecoder");
        Class<?> decoderCompanion = Class.forName(
            "tachiyomi.decoder.ImageDecoder$Companion"
        );
        decoder.getMethod("decode", rect, int.class);
        decoder.getMethod(
            "decode",
            rect,
            boolean.class,
            int.class,
            boolean.class,
            byte[].class
        );
        decoder.getMethod("decode", rect, boolean.class, int.class);
        decoderCompanion.getMethod(
            "newInstance",
            InputStream.class,
            boolean.class,
            byte[].class
        );
        decoderCompanion.getMethod(
            "newInstance",
            InputStream.class,
            boolean.class
        );

        Class<?> quickJs = Class.forName("app.cash.quickjs.QuickJs");
        quickJs.getMethod("evaluate", String.class);
        quickJs.getMethod("get", String.class, Class.class);
        Class.forName("app.cash.quickjs.QuickJsException")
            .getConstructor(String.class);
        Class<?> cookieManagerType = Class.forName(
            "android.webkit.CookieManager"
        );
        cookieManagerType.getMethod("getInstance");
        Class<?> activityManagerType = Class.forName(
            "android.app.ActivityManager"
        );
        Class<?> memoryInfoType = Class.forName(
            "android.app.ActivityManager$MemoryInfo"
        );
        activityManagerType.getMethod(
            "getMemoryInfo",
            memoryInfoType
        );
        Object activityManager = activityManagerType
            .getConstructor()
            .newInstance();
        Object memoryInfo = memoryInfoType.getConstructor().newInstance();
        activityManagerType.getMethod("getMemoryInfo", memoryInfoType)
            .invoke(activityManager, memoryInfo);
        if (memoryInfoType.getField("totalMem").getLong(memoryInfo) <= 0) {
            throw new AssertionError("Activity memory information is invalid");
        }
        Class.forName("android.content.SharedPreferences");
        Class.forName("android.widget.Toast").getMethod(
            "makeText",
            Class.forName("android.content.Context"),
            CharSequence.class,
            int.class
        );
        Class.forName("android.os.Looper").getMethod("getMainLooper");

        byte[] decoded = (byte[]) Class.forName("android.util.Base64")
            .getMethod("decode", String.class, int.class)
            .invoke(null, "VGFjaGl5b21pQVo=", 0);
        if (!"TachiyomiAZ".equals(new String(decoded, StandardCharsets.UTF_8))) {
            throw new AssertionError("Android Base64 decoding failed");
        }

        byte[] key = new byte[16];
        byte[] iv = new byte[16];
        Arrays.fill(key, (byte) 7);
        Cipher cipher = Cipher.getInstance("AES/CBC/PKCS5Padding");
        cipher.init(
            Cipher.ENCRYPT_MODE,
            new SecretKeySpec(key, "AES"),
            new IvParameterSpec(iv)
        );
        byte[] encrypted = cipher.doFinal("compatibility".getBytes("UTF-8"));
        cipher.init(
            Cipher.DECRYPT_MODE,
            new SecretKeySpec(key, "AES"),
            new IvParameterSpec(iv)
        );
        if (!"compatibility".equals(new String(cipher.doFinal(encrypted), "UTF-8"))) {
            throw new AssertionError("AES-CBC compatibility failed");
        }
        Class.forName("java.text.Collator").getMethod(
            "getInstance",
            java.util.Locale.class
        ).invoke(null, java.util.Locale.ENGLISH);

        System.out.println("Android compatibility surface test passed");
    }
}
