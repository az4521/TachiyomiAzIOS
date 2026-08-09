import Darwin
import Foundation
import WebKit

/// Synchronous C entry point used by JNI. JVM extension calls run on utility
/// threads, while every WebKit operation is forwarded to the main actor.
@_cdecl("tachiyomiaz_webkit_command")
func tachiyomiazWebKitCommand(
    _ operationPointer: UnsafePointer<CChar>?,
    _ handle: Int64,
    _ argument1Pointer: UnsafePointer<CChar>?,
    _ argument2Pointer: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    guard !Thread.isMainThread else {
        return copiedCString("__UNAVAILABLE__Android WebView command arrived on the iOS main thread")
    }
    let operation = operationPointer.map { String(cString: $0) } ?? ""
    let argument1 = argument1Pointer.map { String(cString: $0) }
    let argument2 = argument2Pointer.map { String(cString: $0) }
    let result = JVMWebKitCommandResult()
    let semaphore = DispatchSemaphore(value: 0)
    Task { @MainActor in
        result.value = await JVMWebKitBridge.shared.command(
            operation: operation,
            handle: handle,
            argument1: argument1,
            argument2: argument2
        )
        semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 65) == .success else {
        return copiedCString("__ERROR__WKWebView command timed out")
    }
    return copiedCString(result.value)
}

private func copiedCString(_ value: String) -> UnsafeMutablePointer<CChar>? {
    value.withCString { strdup($0) }
}

private final class JVMWebKitCommandResult: @unchecked Sendable {
    var value = ""
}

@MainActor
final class JVMWebKitBridge {
    static let shared = JVMWebKitBridge()

    private var nextHandle: Int64 = 1
    private var contexts: [Int64: Context] = [:]

    func command(
        operation: String,
        handle: Int64,
        argument1: String?,
        argument2: String?
    ) async -> String {
        switch operation {
            case "create":
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = argument1 == "true"
                    ? .nonPersistent()
                    : .default()
                let context = Context(configuration: configuration)
                let newHandle = nextHandle
                nextHandle += 1
                contexts[newHandle] = context
                return String(newHandle)
            case "cookieSet":
                return await setCookie(urlString: argument1, header: argument2)
            case "cookieGet":
                return await cookies(for: argument1)
            case "cookieRemoveSession":
                return await removeCookies(sessionOnly: true)
            case "cookieRemoveAll":
                return await removeCookies(sessionOnly: false)
            case "cookieHas":
                return String(!(await allCookies()).isEmpty)
            case "cookieFlush":
                await copyWebKitCookiesToHTTPStorage(store: .default().httpCookieStore)
                return "true"
            default:
                break
        }

        guard let context = contexts[handle] else {
            return "__ERROR__Unknown WKWebView handle"
        }
        switch operation {
            case "destroy":
                context.cancelPending(message: "WebView was destroyed")
                context.webView.stopLoading()
                contexts[handle] = nil
                return "true"
            case "userAgent":
                context.webView.customUserAgent = argument1
                return "true"
            case "javaScript":
                context.webView.configuration.defaultWebpagePreferences
                    .allowsContentJavaScript = argument1 == "true"
                return "true"
            case "load":
                guard let value = argument1, let url = URL(string: value) else {
                    return "__ERROR__Invalid WebView URL"
                }
                await copyHTTPCookiesToWebKit(store: context.cookieStore, for: url)
                var request = URLRequest(url: url)
                for (key, value) in decodeHeaders(argument2) {
                    request.setValue(value, forHTTPHeaderField: key)
                }
                return await context.load(request: request)
            case "post":
                guard let value = argument1, let url = URL(string: value) else {
                    return "__ERROR__Invalid WebView URL"
                }
                await copyHTTPCookiesToWebKit(store: context.cookieStore, for: url)
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.httpBody = argument2.flatMap { Data(base64Encoded: $0) }
                return await context.load(request: request)
            case "loadHTML":
                guard
                    let encoded = argument2,
                    let data = Data(base64Encoded: encoded),
                    let html = String(data: data, encoding: .utf8)
                else {
                    return "__ERROR__Invalid WebView HTML"
                }
                let baseURL = argument1.flatMap(URL.init(string:))
                return await context.load(html: html, baseURL: baseURL)
            case "evaluate":
                do {
                    let value = try await context.webView.evaluateJavaScript(argument1 ?? "")
                    return Self.jsonString(value)
                } catch {
                    return "__ERROR__\(error.localizedDescription)"
                }
            case "stop":
                context.webView.stopLoading()
                context.cancelPending(message: "Navigation stopped")
                return "true"
            case "reload":
                guard let request = context.webView.url.map(URLRequest.init(url:)) else { return "false" }
                return await context.load(request: request)
            case "goBack":
                return await context.navigate(context.webView.goBack())
            case "goForward":
                return await context.navigate(context.webView.goForward())
            case "go":
                let offset = Int(argument1 ?? "") ?? 0
                let list = context.webView.backForwardList
                let item = offset < 0
                    ? list.backList[safe: max(0, list.backList.count + offset)]
                    : list.forwardList[safe: max(0, offset - 1)]
                let navigation = item.flatMap { context.webView.go(to: $0) }
                return await context.navigate(navigation)
            case "canGoBack": return String(context.webView.canGoBack)
            case "canGoForward": return String(context.webView.canGoForward)
            case "canGo":
                let offset = Int(argument1 ?? "") ?? 0
                return String(offset < 0
                    ? context.webView.backForwardList.backList.count >= -offset
                    : context.webView.backForwardList.forwardList.count >= offset)
            case "url": return context.webView.url?.absoluteString ?? ""
            case "originalUrl": return context.originalURL?.absoluteString ?? ""
            case "title": return context.webView.title ?? ""
            case "progress": return String(Int((context.webView.estimatedProgress * 100).rounded()))
            case "contentHeight": return await dimension(context, expression: "document.documentElement.scrollHeight")
            case "contentWidth": return await dimension(context, expression: "document.documentElement.scrollWidth")
            case "clearHistory":
                // WKWebView exposes no public history reset API. Recreating the
                // context would invalidate the Java WebView handle, so keep the
                // current page and report success.
                return "true"
            case "clearCache":
                let types = WKWebsiteDataStore.allWebsiteDataTypes()
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    context.webView.configuration.websiteDataStore.removeData(
                        ofTypes: types,
                        modifiedSince: .distantPast
                    ) { continuation.resume() }
                }
                return "true"
            default:
                return "__ERROR__Unsupported WKWebView command: \(operation)"
        }
    }

    private func dimension(_ context: Context, expression: String) async -> String {
        let value = try? await context.webView.evaluateJavaScript(expression)
        return String((value as? NSNumber)?.intValue ?? 0)
    }

    private func setCookie(urlString: String?, header: String?) async -> String {
        guard
            let urlString,
            let url = URL(string: urlString),
            let header
        else { return "false" }
        let cookies = HTTPCookie.cookies(
            withResponseHeaderFields: ["Set-Cookie": header],
            for: url
        )
        guard !cookies.isEmpty else { return "false" }
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
            await set(cookie, in: WKWebsiteDataStore.default().httpCookieStore)
        }
        return "true"
    }

    private func cookies(for urlString: String?) async -> String {
        guard let urlString, let url = URL(string: urlString) else { return "" }
        return (await allCookies())
            .filter { Self.cookie($0, matches: url) }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

    private func allCookies() async -> [HTTPCookie] {
        await WKWebsiteDataStore.default().httpCookieStore.allCookies()
    }

    private func removeCookies(sessionOnly: Bool) async -> String {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await store.allCookies()
        let removing = sessionOnly ? cookies.filter { $0.expiresDate == nil } : cookies
        for cookie in removing {
            await delete(cookie, from: store)
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        return String(!removing.isEmpty)
    }

    private func copyHTTPCookiesToWebKit(store: WKHTTPCookieStore, for url: URL) async {
        for cookie in HTTPCookieStorage.shared.cookies(for: url) ?? [] {
            await set(cookie, in: store)
        }
    }

    fileprivate func copyWebKitCookiesToHTTPStorage(store: WKHTTPCookieStore) async {
        for cookie in await store.allCookies() {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    private func set(_ cookie: HTTPCookie, in store: WKHTTPCookieStore) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.setCookie(cookie) { continuation.resume() }
        }
    }

    private func delete(_ cookie: HTTPCookie, from store: WKHTTPCookieStore) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.delete(cookie) { continuation.resume() }
        }
    }

    private static func cookie(_ cookie: HTTPCookie, matches url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        guard host == domain || host.hasSuffix("." + domain) else { return false }
        guard url.path.hasPrefix(cookie.path) else { return false }
        guard !cookie.isSecure || url.scheme?.lowercased() == "https" else { return false }
        return cookie.expiresDate.map { $0 > Date() } ?? true
    }

    private static func jsonString(_ value: Any?) -> String {
        guard let value else { return "null" }
        guard JSONSerialization.isValidJSONObject([value]) else {
            return "null"
        }
        guard
            let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed),
            let string = String(data: data, encoding: .utf8)
        else { return "null" }
        return string
    }

    private func decodeHeaders(_ value: String?) -> [(String, String)] {
        guard let value, !value.isEmpty else { return [] }
        return value.split(separator: "\n").compactMap { line in
            let pieces = line.split(separator: ":", maxSplits: 1)
            guard
                pieces.count == 2,
                let keyData = Data(base64Encoded: String(pieces[0])),
                let valueData = Data(base64Encoded: String(pieces[1])),
                let key = String(data: keyData, encoding: .utf8),
                let value = String(data: valueData, encoding: .utf8)
            else { return nil }
            return (key, value)
        }
    }

    final class Context: NSObject, WKNavigationDelegate {
        let webView: WKWebView
        var originalURL: URL?
        var continuation: CheckedContinuation<String, Never>?
        var timeoutTask: Task<Void, Never>?

        var cookieStore: WKHTTPCookieStore {
            webView.configuration.websiteDataStore.httpCookieStore
        }

        init(configuration: WKWebViewConfiguration) {
            webView = WKWebView(frame: .zero, configuration: configuration)
            super.init()
            webView.navigationDelegate = self
        }

        func load(request: URLRequest) async -> String {
            originalURL = request.url
            return await waitForNavigation { webView.load(request) }
        }

        func load(html: String, baseURL: URL?) async -> String {
            originalURL = baseURL
            return await waitForNavigation { webView.loadHTMLString(html, baseURL: baseURL) }
        }

        func navigate(_ navigation: WKNavigation?) async -> String {
            guard navigation != nil else { return "false" }
            return await waitForNavigation { navigation }
        }

        private func waitForNavigation(_ start: () -> WKNavigation?) async -> String {
            cancelPending(message: "Superseded by another navigation")
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                guard start() != nil else {
                    complete("__ERROR__WKWebView rejected the navigation")
                    return
                }
                timeoutTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 45_000_000_000)
                    guard !Task.isCancelled else { return }
                    self?.webView.stopLoading()
                    self?.complete("__ERROR__WKWebView navigation timed out")
                }
            }
        }

        func cancelPending(message: String) {
            guard continuation != nil else { return }
            complete("__ERROR__\(message)")
        }

        private func complete(_ value: String) {
            guard let continuation else { return }
            self.continuation = nil
            timeoutTask?.cancel()
            timeoutTask = nil
            continuation.resume(returning: value)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                await JVMWebKitBridge.shared.copyWebKitCookiesToHTTPStorage(store: cookieStore)
                complete(webView.url?.absoluteString ?? originalURL?.absoluteString ?? "")
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            complete("__ERROR__\(error.localizedDescription)")
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            complete("__ERROR__\(error.localizedDescription)")
        }
    }
}
