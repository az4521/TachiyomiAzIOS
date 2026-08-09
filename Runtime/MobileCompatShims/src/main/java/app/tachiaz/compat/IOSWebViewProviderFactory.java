package app.tachiaz.compat;

import android.graphics.Bitmap;
import android.webkit.CookieManager;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebViewProvider;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.net.CookieHandler;
import java.net.HttpCookie;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import xyz.nulldev.androidcompat.CallableArgument;
import xyz.nulldev.androidcompat.webkit.KcefWebSettings;

/**
 * Replaces Suwayomi's desktop KCEF backend with the WKWebView backend exposed
 * by the iOS app. AndroidCompat's public android.webkit classes stay intact,
 * so extensions continue to call the same API they use under Mihon.
 */
public final class IOSWebViewProviderFactory
    implements CallableArgument<WebView, WebViewProvider> {

    public static void install() throws Exception {
        WebView.setProviderFactory(new IOSWebViewProviderFactory());
        Field singleton = CookieManager.class.getDeclaredField("INSTANCE");
        singleton.setAccessible(true);
        singleton.set(null, new IOSCookieManager());
    }

    @Override
    public WebViewProvider call(WebView view) {
        InvocationHandler handler = new Provider(view);
        return (WebViewProvider) Proxy.newProxyInstance(
            WebViewProvider.class.getClassLoader(),
            new Class<?>[] {WebViewProvider.class},
            handler
        );
    }

    private static final class Provider implements InvocationHandler {
        private final WebView view;
        private final WebSettings settings = new KcefWebSettings();
        private long handle;
        private WebViewClient webViewClient = new WebViewClient();
        private WebChromeClient webChromeClient;
        private boolean paused;

        Provider(WebView view) {
            this.view = view;
            String value = command("create", 0, "false", null);
            try {
                handle = Long.parseLong(value);
            } catch (RuntimeException error) {
                throw new IllegalStateException(
                    "Unable to create the iOS WebView backend: " + value,
                    error
                );
            }
        }

        @Override
        public Object invoke(Object proxy, Method method, Object[] arguments) {
            String name = method.getName();
            Object[] args = arguments == null ? new Object[0] : arguments;
            if (name.equals("toString")) return "IOSWebViewProvider(" + handle + ")";
            if (name.equals("hashCode")) return System.identityHashCode(this);
            if (name.equals("equals")) return proxy == args[0];

            switch (name) {
                case "init":
                    return null;
                case "destroy":
                    if (handle != 0) {
                        command("destroy", handle, null, null);
                        handle = 0;
                    }
                    return null;
                case "loadUrl":
                    loadUrl((String) args[0], args.length > 1 ? castHeaders(args[1]) : null);
                    return null;
                case "postUrl":
                    loadPost((String) args[0], (byte[]) args[1]);
                    return null;
                case "loadData":
                    loadData(null, (String) args[0], (String) args[2]);
                    return null;
                case "loadDataWithBaseURL":
                    loadData((String) args[0], (String) args[1], (String) args[3]);
                    return null;
                case "evaluateJavaScript":
                    String result = command("evaluate", handle, (String) args[0], null);
                    if (args.length > 1 && args[1] != null) {
                        @SuppressWarnings("unchecked")
                        ValueCallback<String> callback = (ValueCallback<String>) args[1];
                        callback.onReceiveValue(result);
                    }
                    return null;
                case "stopLoading": return run("stop");
                case "reload": return run("reload");
                case "goBack": return run("goBack");
                case "goForward": return run("goForward");
                case "goBackOrForward":
                    return run("go", Integer.toString((Integer) args[0]));
                case "canGoBack": return bool(command("canGoBack", handle, null, null));
                case "canGoForward": return bool(command("canGoForward", handle, null, null));
                case "canGoBackOrForward":
                    return bool(command("canGo", handle, Integer.toString((Integer) args[0]), null));
                case "getUrl": return emptyToNull(command("url", handle, null, null));
                case "getOriginalUrl": return emptyToNull(command("originalUrl", handle, null, null));
                case "getTitle": return emptyToNull(command("title", handle, null, null));
                case "getProgress": return integer(command("progress", handle, null, null));
                case "getContentHeight": return integer(command("contentHeight", handle, null, null));
                case "getContentWidth": return integer(command("contentWidth", handle, null, null));
                case "clearCache": return run("clearCache", Boolean.toString((Boolean) args[0]));
                case "clearHistory": return run("clearHistory");
                case "onPause": paused = true; return null;
                case "onResume": paused = false; return null;
                case "isPaused": return paused;
                case "isPrivateBrowsingEnabled": return false;
                case "setWebViewClient":
                    webViewClient = args[0] == null ? new WebViewClient() : (WebViewClient) args[0];
                    return null;
                case "getWebViewClient": return webViewClient;
                case "setWebChromeClient": webChromeClient = (WebChromeClient) args[0]; return null;
                case "getWebChromeClient": return webChromeClient;
                case "getSettings": return settings;
                case "insertVisualStateCallback":
                    if (args[1] != null) {
                        ((WebView.VisualStateCallback) args[1]).onComplete((Long) args[0]);
                    }
                    return null;
                case "getViewDelegate":
                case "getScrollDelegate":
                    return defaultProxy(method.getReturnType());
                case "zoomBy":
                case "zoomIn":
                case "zoomOut": return false;
                case "getScale": return 1.0f;
                case "getRendererRequestedPriority": return 0;
                case "getRendererPriorityWaivedWhenNotVisible": return false;
                default:
                    return defaultValue(method.getReturnType());
            }
        }

        private void loadUrl(String url, Map<String, String> headers) {
            if (webViewClient.shouldOverrideUrlLoading(view, url)) return;
            start(url);
            String result = command("load", handle, url, encodeHeaders(headers));
            finish(url, result);
        }

        private void loadPost(String url, byte[] data) {
            if (webViewClient.shouldOverrideUrlLoading(view, url)) return;
            start(url);
            String body = Base64.getEncoder().encodeToString(data);
            finish(url, command("post", handle, url, body));
        }

        private void loadData(String baseUrl, String data, String encoding) {
            String url = baseUrl == null ? "about:blank" : baseUrl;
            start(url);
            String encoded = "base64".equalsIgnoreCase(encoding)
                ? data
                : Base64.getEncoder().encodeToString(data.getBytes(StandardCharsets.UTF_8));
            finish(url, command("loadHTML", handle, baseUrl, encoded));
        }

        private void start(String url) {
            applySettings();
            if (webChromeClient != null) {
                webChromeClient.onProgressChanged(view, 0);
            }
            webViewClient.onPageStarted(view, url, (Bitmap) null);
        }

        private void finish(String requestedUrl, String result) {
            if (result != null && result.startsWith("__ERROR__")) {
                webViewClient.onReceivedError(
                    view,
                    -1,
                    result.substring("__ERROR__".length()),
                    requestedUrl
                );
                if (webChromeClient != null) {
                    webChromeClient.onProgressChanged(view, 100);
                }
                return;
            }
            String finalUrl = result == null || result.isEmpty() ? requestedUrl : result;
            webViewClient.onPageCommitVisible(view, finalUrl);
            webViewClient.onPageFinished(view, finalUrl);
            if (webChromeClient != null) {
                webChromeClient.onReceivedTitle(
                    view,
                    emptyToNull(command("title", handle, null, null))
                );
                webChromeClient.onProgressChanged(view, 100);
            }
        }

        private void applySettings() {
            String userAgent = settings.getUserAgentString();
            if (userAgent != null && !userAgent.isEmpty()) {
                command("userAgent", handle, userAgent, null);
            }
            command(
                "javaScript",
                handle,
                Boolean.toString(settings.getJavaScriptEnabled()),
                null
            );
        }

        private Object run(String operation) {
            command(operation, handle, null, null);
            return null;
        }

        private Object run(String operation, String argument) {
            command(operation, handle, argument, null);
            return null;
        }

        @SuppressWarnings("unchecked")
        private static Map<String, String> castHeaders(Object value) {
            return value == null ? Collections.<String, String>emptyMap() : (Map<String, String>) value;
        }

        private static String encodeHeaders(Map<String, String> headers) {
            if (headers == null || headers.isEmpty()) return "";
            StringBuilder output = new StringBuilder();
            Base64.Encoder encoder = Base64.getEncoder();
            for (Map.Entry<String, String> entry : headers.entrySet()) {
                if (output.length() > 0) output.append('\n');
                output.append(encoder.encodeToString(entry.getKey().getBytes(StandardCharsets.UTF_8)));
                output.append(':');
                output.append(encoder.encodeToString(entry.getValue().getBytes(StandardCharsets.UTF_8)));
            }
            return output.toString();
        }

        private static Object defaultProxy(Class<?> type) {
            return Proxy.newProxyInstance(
                type.getClassLoader(),
                new Class<?>[] {type},
                (proxy, method, args) -> defaultValue(method.getReturnType())
            );
        }
    }

    private static final class IOSCookieManager extends CookieManager {
        private final java.net.CookieManager javaCookies;
        private boolean acceptCookies = true;
        private boolean acceptThirdPartyCookies = true;
        private boolean acceptFileCookies;

        IOSCookieManager() {
            CookieHandler handler = CookieHandler.getDefault();
            javaCookies = handler instanceof java.net.CookieManager
                ? (java.net.CookieManager) handler
                : new java.net.CookieManager();
            if (!(handler instanceof java.net.CookieManager)) {
                CookieHandler.setDefault(javaCookies);
            }
        }

        @Override public void setAcceptCookie(boolean accept) { acceptCookies = accept; }
        @Override public boolean acceptCookie() { return acceptCookies; }
        @Override public void setAcceptThirdPartyCookies(WebView view, boolean accept) {
            acceptThirdPartyCookies = accept;
        }
        @Override public boolean acceptThirdPartyCookies(WebView view) {
            return acceptThirdPartyCookies;
        }

        @Override public void setCookie(String url, String value) {
            if (!acceptCookies || value == null) return;
            command("cookieSet", 0, url, value);
            try {
                URI uri = normalizedUri(url);
                for (HttpCookie cookie : HttpCookie.parse(value)) {
                    javaCookies.getCookieStore().add(uri, cookie);
                }
            } catch (RuntimeException ignored) {
                // WebKit remains the authoritative browser cookie store.
            }
        }

        @Override public void setCookie(String url, String value, ValueCallback<Boolean> callback) {
            setCookie(url, value);
            if (callback != null) callback.onReceiveValue(true);
        }

        @Override public String getCookie(String url) {
            return emptyToNull(command("cookieGet", 0, url, null));
        }

        @Deprecated @Override public void removeSessionCookie() {
            removeSessionCookies(null);
        }
        @Override public void removeSessionCookies(ValueCallback<Boolean> callback) {
            boolean removed = bool(command("cookieRemoveSession", 0, null, null));
            removeJavaSessionCookies();
            if (callback != null) callback.onReceiveValue(removed);
        }
        @Deprecated @Override public void removeExpiredCookie() {}
        @Deprecated @Override public void removeAllCookie() { removeAllCookies(null); }
        @Override public void removeAllCookies(ValueCallback<Boolean> callback) {
            boolean removed = bool(command("cookieRemoveAll", 0, null, null));
            javaCookies.getCookieStore().removeAll();
            if (callback != null) callback.onReceiveValue(removed);
        }
        @Override public boolean hasCookies() {
            return bool(command("cookieHas", 0, null, null));
        }
        @Override public void flush() { command("cookieFlush", 0, null, null); }
        @Override public boolean allowFileSchemeCookiesImpl() { return acceptFileCookies; }
        @Override public void setAcceptFileSchemeCookiesImpl(boolean accept) {
            acceptFileCookies = accept;
        }

        private static URI normalizedUri(String value) {
            return URI.create(value.startsWith("http") ? value : "http://" + value);
        }

        private void removeJavaSessionCookies() {
            List<URI> uris = new ArrayList<>(javaCookies.getCookieStore().getURIs());
            for (URI uri : uris) {
                List<HttpCookie> cookies = new ArrayList<>(
                    javaCookies.getCookieStore().get(uri)
                );
                for (HttpCookie cookie : cookies) {
                    if (cookie.getMaxAge() < 0) {
                        javaCookies.getCookieStore().remove(uri, cookie);
                    }
                }
            }
        }
    }

    private static String command(
        String operation,
        long handle,
        String argument1,
        String argument2
    ) {
        String result = NativeBridge.webkitCommand(operation, handle, argument1, argument2);
        if (result != null && result.startsWith("__UNAVAILABLE__")) {
            throw new UnsupportedOperationException(result.substring("__UNAVAILABLE__".length()));
        }
        return result == null ? "" : result;
    }

    private static boolean bool(String value) { return "true".equalsIgnoreCase(value); }
    private static int integer(String value) {
        try { return Integer.parseInt(value); } catch (RuntimeException ignored) { return 0; }
    }
    private static String emptyToNull(String value) {
        return value == null || value.isEmpty() ? null : value;
    }
    private static Object defaultValue(Class<?> type) {
        if (!type.isPrimitive() || type == Void.TYPE) return null;
        if (type == Boolean.TYPE) return false;
        if (type == Character.TYPE) return '\0';
        if (type == Byte.TYPE) return (byte) 0;
        if (type == Short.TYPE) return (short) 0;
        if (type == Integer.TYPE) return 0;
        if (type == Long.TYPE) return 0L;
        if (type == Float.TYPE) return 0f;
        if (type == Double.TYPE) return 0d;
        return null;
    }
}
