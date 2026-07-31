//
//  WebView.swift
//  Aidoku
//
//  Created by Skitty on 5/21/25.
//

import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let url: URL
    let localStorageKeys: [String]

    @Binding var cookies: [String: String]
    @Binding var detailedCookies: [HTTPCookie]
    @Binding var localStorage: [String: String]
    @Binding var userAgent: String
    @Binding var reloadToggle: Bool

    let preferredUserAgent: String?

    private let webView = WKWebView()

    init(
        _ url: URL,
        localStorageKeys: [String] = [],
        cookies: Binding<[String: String]> = .constant([:]),
        detailedCookies: Binding<[HTTPCookie]> = .constant([]),
        localStorage: Binding<[String: String]> = .constant([:]),
        userAgent: Binding<String> = .constant(""),
        preferredUserAgent: String? = nil,
        reloadToggle: Binding<Bool> = .constant(false)
    ) {
        self.url = url
        self.localStorageKeys = localStorageKeys
        self._cookies = cookies
        self._detailedCookies = detailedCookies
        self._localStorage = localStorage
        self._userAgent = userAgent
        self.preferredUserAgent = preferredUserAgent
        self._reloadToggle = reloadToggle
    }

    func makeUIView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = preferredUserAgent
        context.coordinator.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if
            let preferredUserAgent,
            !preferredUserAgent.isEmpty,
            uiView.customUserAgent != preferredUserAgent
        {
            uiView.customUserAgent = preferredUserAgent
            uiView.reload()
        }
        if reloadToggle {
            reloadToggle = false
            uiView.reload()
        }
    }

    func makeCoordinator() -> Coordinator {
        .init(parent: self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        var parent: WebView
        weak var webView: WKWebView?

        init(parent: WebView) {
            self.parent = parent
            super.init()
            WKWebsiteDataStore.default().httpCookieStore.add(self)
        }

        deinit {
            WKWebsiteDataStore.default().httpCookieStore.remove(self)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task {
                await updateState(from: webView)
                if !parent.localStorageKeys.isEmpty {
                    let storage = await webView.getLocalStorage(keys: parent.localStorageKeys)
                    await MainActor.run {
                        parent.localStorage = storage
                    }
                }
            }
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            guard let webView else { return }
            Task {
                await updateState(from: webView)
                if !parent.localStorageKeys.isEmpty {
                    let storage = await webView.getLocalStorage(keys: parent.localStorageKeys)
                    await MainActor.run {
                        parent.localStorage = storage
                    }
                }
            }
        }

        private func updateState(from webView: WKWebView) async {
            let allCookies = await webView.configuration.websiteDataStore
                .httpCookieStore
                .allCookies()
            let matching = allCookies.filter {
                Self.cookie($0, matchesHost: parent.url.host)
            }
            let cookieValues = Dictionary(
                matching.map { ($0.name, $0.value) },
                uniquingKeysWith: { _, latest in latest }
            )
            let currentUserAgent = (
                try? await webView.evaluateJavaScript("navigator.userAgent")
            ) as? String ?? ""
            await MainActor.run {
                parent.cookies = cookieValues
                parent.detailedCookies = matching
                parent.userAgent = currentUserAgent
            }
        }

        private static func cookie(
            _ cookie: HTTPCookie,
            matchesHost hostValue: String?
        ) -> Bool {
            guard let host = hostValue?.lowercased() else { return false }
            let domain = cookie.domain
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .lowercased()
            return host == domain || host.hasSuffix("." + domain)
        }
    }
}
