package app.tachiaz.runtime;

/**
 * Proves that the mobile boot shim replaces only SystemClock while the full
 * AndroidCompat API remains visible ahead of the host's test fixtures.
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

        System.out.println("mobile shim precedence test passed");
    }
}
