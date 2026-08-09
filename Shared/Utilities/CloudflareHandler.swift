//
//  CloudflareHandler.swift
//  Aidoku
//
//  Created by Skitty on 6/15/25.
//

import AidokuRunner
import SwiftSoup
import WebKit

// handles requests blocked by cloudflare, retrieving new cookies from a webview
// and showing a popup to complete a captcha if necessary
actor CloudflareHandler: NSObject {
    static let shared = CloudflareHandler()

    private let blockedStatusCodes: Set<Int> = [403, 503]

    private var finishContinuation: CheckedContinuation<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var proxy: Proxy?
    private var lastMainFrameStatusCode: Int?
    private var completionReason: CompletionReason?
    private var recentSessions: [String: (Date, Session)] = [:]

    @MainActor
    private lazy var webView = WKWebView(frame: .zero)

#if !os(macOS)
    @MainActor
    private var popupController: WebViewViewController?

    @MainActor
    private var popupPresentationActive = false
#endif

    @MainActor
    private var popupShown: Bool {
#if !os(macOS)
        popupPresentationActive
#else
        false
#endif
    }

#if os(macOS)
    @MainActor
    private var parent: NSWindow? {
        NSApplication.shared.windows.first
    }

    @MainActor
    private var parentView: NSView? {
        parent?.contentView
    }
#else
    @MainActor
    private var parent: UIViewController? {
        (UIApplication.shared.delegate as? AppDelegate)?.visibleViewController
    }

    @MainActor
    private var parentView: UIView? {
        parent?.view
    }
#endif

    struct Session {
        let cookies: [HTTPCookie]
        let userAgent: String
    }

    enum HandleError: LocalizedError {
        case missingParentView
        case cancelled
        case timedOut
        case missingClearance

        var errorDescription: String? {
            switch self {
                case .missingParentView:
                    "Cloudflare verification needs a visible app window."
                case .cancelled:
                    "Cloudflare verification was cancelled."
                case .timedOut:
                    "Cloudflare verification timed out."
                case .missingClearance:
                    "Cloudflare did not issue a clearance cookie."
            }
        }
    }

    private enum CompletionReason {
        case solved
        case cancelled
        case timedOut
    }

    nonisolated func shouldHandle(response: HTTPURLResponse, data: Data) -> Bool {
        let server = response.value(forHTTPHeaderField: "Server")
        if !["cloudflare", "cloudflare-nginx"].contains(server) {
            return false
        }
        if !blockedStatusCodes.contains(response.statusCode) {
            return false
        }

        guard let html = String(data: data, encoding: .utf8) else { return false }
        do {
            let doc = try SwiftSoup.parse(html)
            if try doc.getElementById("challenge-error-title") != nil {
                return true
            }
            if try doc.getElementById("challenge-error-text") != nil {
                return true
            }
        } catch {}
        return false
    }

    func handle(request: URLRequest) async throws -> (Data, URLResponse) {
        _ = try await solve(request: request)
        let newRequest = if let url = request.url {
            await AidokuRunner.Source.modify(url: url, request: request)
        } else {
            request
        }
        return try await URLSession.shared.data(for: newRequest)
    }

    func solve(request: URLRequest) async throws -> Session {
        // wait until previous request finishes
        while finishContinuation != nil {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        let sessionKey = cacheKey(for: request)
        if
            let cached = recentSessions[sessionKey],
            Date().timeIntervalSince(cached.0) < 30,
            cached.1.cookies.contains(where: { $0.name == "cf_clearance" })
        {
            return cached.1
        }

        completionReason = nil

        guard let url = request.url else { throw HandleError.missingClearance }
        await removeStaleClearanceCookies(for: url)

        guard await addWebView(for: request) else { throw HandleError.missingParentView }

        _ = await webView.load(request)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.finishContinuation = continuation

            // Managed challenges normally finish without interaction. Keep a
            // finite deadline so a stalled challenge can never leave the UI
            // spinning indefinitely.
            self.scheduleTimeout(after: 45_000_000_000)
        }

        switch completionReason {
            case .cancelled:
                throw HandleError.cancelled
            case .timedOut:
                throw HandleError.timedOut
            case .solved:
                break
            case nil:
                throw HandleError.missingClearance
        }

        let cookies = await WKWebsiteDataStore.default()
            .httpCookieStore
            .allCookies()
            .filter { cookieMatches($0, url: url) }
        guard cookies.contains(where: { $0.name == "cf_clearance" }) else {
            throw HandleError.missingClearance
        }
        let userAgent = request.value(forHTTPHeaderField: "User-Agent") ?? ""
        let session = Session(cookies: cookies, userAgent: userAgent)
        recentSessions[sessionKey] = (Date(), session)
        return session
    }

    func clearWebSession(for url: URL) async {
        if let host = url.host?.lowercased() {
            recentSessions = recentSessions.filter {
                !$0.key.hasPrefix(host + "\n")
            }
        }
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        for cookie in await cookieStore.allCookies()
        where cookieMatches(cookie, url: url) {
            await withCheckedContinuation {
                (continuation: CheckedContinuation<Void, Never>) in
                cookieStore.delete(cookie) {
                    continuation.resume()
                }
            }
        }
        for cookie in HTTPCookieStorage.shared.cookies(for: url) ?? [] {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    private func finish(reason: CompletionReason) async {
        guard finishContinuation != nil, completionReason == nil else { return }
        completionReason = reason

        // Keep finishContinuation set until the UI is gone. That prevents a
        // new challenge from replacing `webView` while this cleanup is queued
        // on the main actor.
        await MainActor.run {
            webView.removeFromSuperview()
#if !os(macOS)
            popupController?.dismiss(animated: true)
            popupController = nil
            popupPresentationActive = false
#endif
        }

        timeoutTask?.cancel()
        let continuation = finishContinuation
        finishContinuation = nil
        timeoutTask = nil
        proxy = nil
        lastMainFrameStatusCode = nil

        continuation?.resume()
    }

    private func removeStaleClearanceCookies(for url: URL) async {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        for cookie in await cookieStore.allCookies()
        where cookie.name == "cf_clearance" && cookieMatches(cookie, url: url) {
            await withCheckedContinuation {
                (continuation: CheckedContinuation<Void, Never>) in
                cookieStore.delete(cookie) {
                    continuation.resume()
                }
            }
        }
        for cookie in HTTPCookieStorage.shared.cookies(for: url) ?? []
        where cookie.name == "cf_clearance" {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    private nonisolated func cookieMatches(_ cookie: HTTPCookie, url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let domain = cookie.domain
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return host == domain || host.hasSuffix("." + domain)
    }

    private nonisolated func cacheKey(for request: URLRequest) -> String {
        let host = request.url?.host?.lowercased() ?? ""
        let userAgent = request.value(forHTTPHeaderField: "User-Agent") ?? ""
        return host + "\n" + userAgent
    }

    private func proxy(for request: URLRequest) async -> Proxy {
        if let proxy {
            return proxy
        }
        let proxy = await Proxy(request: request, handler: self)
        self.proxy = proxy
        return proxy
    }

    // add hidden web view to a visible view controller
    @MainActor
    private func addWebView(for request: URLRequest) async -> Bool {
        guard let parentView else { return false }

        // A zero-sized viewport causes some managed challenges to continually
        // restart their browser check. Give WebKit the device viewport while
        // keeping the automatic verifier visually unobtrusive.
        let viewport = parentView.bounds.isEmpty
            ? CGRect(x: 0, y: 0, width: 390, height: 844)
            : parentView.bounds
        webView = WKWebView(frame: viewport)
        webView.navigationDelegate = await proxy(for: request)
        webView.customUserAgent = request.value(forHTTPHeaderField: "User-Agent")
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.isUserInteractionEnabled = false
        webView.alpha = 0.01
        parentView.insertSubview(webView, at: 0)

        return true
    }

    private func scheduleTimeout(after nanoseconds: UInt64) {
        timeoutTask?.cancel()
        timeoutTask = Task {
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, finishContinuation != nil else { return }
            await finish(reason: .timedOut)
        }
    }

    // show captcha sheet view to user
    @MainActor
    private func showPopup(for request: URLRequest) async {
        guard !popupShown else { return }

#if !os(macOS)
        // Set this before crossing back to the handler actor so delayed
        // navigation checks cannot present a second sheet during animation.
        popupPresentationActive = true
#endif

        // Interactive challenges need longer, but must still have a deadline.
        await scheduleTimeout(after: 120_000_000_000)

#if os(macOS)
        // todo
        await finish(reason: .cancelled)
#else
        popupController?.dismiss(animated: true)
        let popup = WebViewViewController(request: request, handler: await proxy(for: request))
        popupController = popup

        webView.navigationDelegate = popup
        webView.removeFromSuperview()
        webView.alpha = 1
        webView.isUserInteractionEnabled = true
        webView.autoresizingMask = []
        webView.translatesAutoresizingMaskIntoConstraints = false
        popup.view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.widthAnchor.constraint(equalTo: popup.view.widthAnchor),
            webView.heightAnchor.constraint(equalTo: popup.view.heightAnchor),
            webView.centerXAnchor.constraint(equalTo: popup.view.centerXAnchor),
            webView.centerYAnchor.constraint(equalTo: popup.view.centerYAnchor)
        ])

        guard let parent else {
            await finish(reason: .cancelled)
            return
        }
        parent.present(popup, animated: true)
#endif
    }

    // check if captcha or verify button is shown, and show the popup if it is
    @MainActor
    private func checkForCaptcha(
        for request: URLRequest,
        includeChallengeFrames: Bool = false
    ) {
        guard !popupShown else { return }
        Task {
            let found = await isCaptchaPage(
                includeChallengeFrames: includeChallengeFrames
            )
            if found {
                await showPopup(for: request)
            }
        }
    }

    @MainActor
    private func isCaptchaPage(
        includeChallengeFrames: Bool = false
    ) async -> Bool {
        let includeChallengeFramesValue = includeChallengeFrames
            ? "true"
            : "false"
        let js = """
        (() => {
            const visible = (element) => {
                if (!element) return false;
                const style = window.getComputedStyle(element);
                const rect = element.getBoundingClientRect();
                return style.display !== 'none'
                    && style.visibility !== 'hidden'
                    && Number(style.opacity || 1) !== 0
                    && rect.width > 0
                    && rect.height > 0;
            };
            const controls = Array.from(document.querySelectorAll(
                '#challenge-stage input:not([type="hidden"]), '
                + '#challenge-stage button, .ctp-checkbox-label'
            ));
            if (\(includeChallengeFramesValue)) {
                controls.push(...document.querySelectorAll(
                    'iframe[src*="challenges.cloudflare.com"], '
                    + 'iframe[title*="Cloudflare"]'
                ));
            }
            return controls.some(visible) ? 1 : 0;
        })()
        """
        let result = try? await webView.evaluateJavaScript(js)
        guard let result = result as? Int else { return false }
        return result == 1
    }
}

extension CloudflareHandler {
    @MainActor
    final class Proxy: NSObject, PopupWebViewHandler, WKNavigationDelegate {
        let request: URLRequest

        weak var handler: CloudflareHandler?

        init(request: URLRequest, handler: CloudflareHandler) {
            self.request = request
            self.handler = handler
        }

        func navigated(webView: WKWebView, for request: URLRequest) {
            Task { [weak handler] in
                await handler?.navigated(webView: webView, for: request)
            }
        }

        func canceled(request: URLRequest) {
            Task { [weak handler] in
                await handler?.canceled(request: request)
            }
        }

        func handle(response: WKNavigationResponse) async {
            guard
                response.isForMainFrame,
                let response = response.response as? HTTPURLResponse
            else { return }
            await handler?.setLastMainFrameStatusCode(response.statusCode)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            navigated(webView: webView, for: request)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            await handle(response: navigationResponse)
            return .allow
        }
    }

    private func setLastMainFrameStatusCode(_ statusCode: Int) {
        lastMainFrameStatusCode = statusCode
    }

    // handle web view reload/redirect
    nonisolated func navigated(webView: WKWebView, for request: URLRequest) async {
        guard let url = request.url else { return }

#if !os(macOS)
        await MainActor.run {
            if self.popupController == nil {
                // delay captcha check by 3s (so it loads in)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.checkForCaptcha(for: request)
                }
                // try again in 5s if the first check didn't catch the captcha (dumb hack)
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                    self?.checkForCaptcha(
                        for: request,
                        includeChallengeFrames: true
                    )
                }
            }
        }
#endif

        var webViewCookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()

        // check for old (expired) clearance cookie
        let oldCookie = HTTPCookieStorage.shared.cookies(for: url)?.first { $0.name == "cf_clearance" }

        // check for clearance cookie
        let hasClearance = webViewCookies.contains(where: {
            $0.name == "cf_clearance" &&
            $0.value != oldCookie?.value ?? "" &&
            ($0.domain.contains(url.host ?? "") || (url.host?.contains($0.domain) ?? false))
        })
        guard hasClearance else { return }

        // remove old cookie and save new cookies for future requests
        if let oldCookie {
            HTTPCookieStorage.shared.deleteCookie(oldCookie)
            if let idx = webViewCookies.firstIndex(of: oldCookie) {
                webViewCookies.remove(at: idx)
            }
        }
        HTTPCookieStorage.shared.setCookies(webViewCookies, for: url, mainDocumentURL: url)

        // ensure we're no longer blocked by cloudflare status or captcha
        if let statusCode = await self.lastMainFrameStatusCode, blockedStatusCodes.contains(statusCode) {
            return
        }
        let isCaptcha = await isCaptchaPage(includeChallengeFrames: true)
        guard !isCaptcha else { return }

        await webView.removeFromSuperview()
#if !os(macOS)
        await self.popupController?.dismiss(animated: true)
#endif

        await self.finish(reason: .solved)
    }

    // handle user popover dismiss
    nonisolated func canceled(request: URLRequest) async {
        await finish(reason: .cancelled)
    }
}
