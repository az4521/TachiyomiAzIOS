//
//  UserAgentProvider.swift
//  Aidoku
//
//  Created by Skitty on 3/24/25.
//

import Foundation
import WebKit

class UserAgentProvider {
    static let shared = UserAgentProvider()

    static let extensionNetworkUserAgentKey =
        "Advanced.extensionNetworkUserAgent"
    static let defaultExtensionNetworkUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) " +
        "Chrome/120.0.0.0 Safari/537.36"

    private var task: Task<String?, Never>?
    private var userAgent: String?

    private init() {
        // start fetching user agent immediately
        task = Task {
            await fetchUserAgent()
        }
    }

    @MainActor
    private func fetchUserAgent() async -> String? {
        let webView = WKWebView()
        do {
            let userAgent = try await webView.evaluateJavaScript("navigator.userAgent") as? String
            self.userAgent = userAgent
            return userAgent
        } catch {
            LogManager.logger.error("Error getting user agent: \(error)")
            return nil
        }
    }

    func getUserAgent() async -> String {
        if let userAgent {
            return userAgent
        }
        return await task?.value ?? ""
    }

    func getUserAgentBlocking() -> String {
        if let userAgent {
            return userAgent
        }
        return BlockingTask {
            await self.getUserAgent()
        }.get()
    }

    func getExtensionNetworkUserAgent() async -> String {
        let configured = UserDefaults.standard.string(
            forKey: Self.extensionNetworkUserAgentKey
        )?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !configured.isEmpty {
            return configured
        }
        return await getUserAgent()
    }
}
