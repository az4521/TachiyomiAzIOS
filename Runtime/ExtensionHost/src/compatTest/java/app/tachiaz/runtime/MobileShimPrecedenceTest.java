package app.tachiaz.runtime;

/**
 * Proves that iOS-native compatibility types come from the mobile boot shim
 * while the remaining AndroidCompat API stays on the application classpath.
 */
public final class MobileShimPrecedenceTest {
    private MobileShimPrecedenceTest() {
    }

    public static void main(String[] args) throws Exception {
        Class<?> systemClock = Class.forName("android.os.SystemClock");
        if (systemClock.getClassLoader() != null) {
            throw new AssertionError(
                "SystemClock must be loaded from the mobile boot shim"
            );
        }

        Class<?> uri = Class.forName("android.net.Uri");
        uri.getMethod("getQueryParameter", String.class);
        if (uri.getClassLoader() == null) {
            throw new AssertionError(
                "Uri must come from the application compatibility classpath"
            );
        }

        Class<?> bitmap = requireBootShim("android.graphics.Bitmap");
        Class<?> rectangle = requireBootShim("android.graphics.Rect");
        Class<?> paint = requireBootShim("android.graphics.Paint");
        Class<?> canvas = requireBootShim("android.graphics.Canvas");
        canvas.getMethod(
            "drawBitmap",
            bitmap,
            rectangle,
            rectangle,
            paint
        );

        Class<?> userAgentInterceptor = Class.forName(
            "eu.kanade.tachiyomi.network.interceptor.UserAgentInterceptor"
        );
        userAgentInterceptor.getMethod("effectiveUserAgent", String.class);

        System.out.println("mobile shim precedence test passed");
    }

    private static Class<?> requireBootShim(String name) throws Exception {
        Class<?> type = Class.forName(name);
        if (type.getClassLoader() != null) {
            throw new AssertionError(name + " must come from the mobile boot shim");
        }
        return type;
    }
}
