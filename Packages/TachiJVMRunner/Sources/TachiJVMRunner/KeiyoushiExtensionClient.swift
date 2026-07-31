import Foundation

public struct KeiyoushiManga: Codable, Sendable, Equatable {
    public let url: String
    public let title: String
    public let thumbnailURL: String?
    public let artist: String?
    public let author: String?
    public let status: Int
    public let description: String?
    public let genre: String?
}

public struct KeiyoushiMangaPage: Codable, Sendable, Equatable {
    public let mangas: [KeiyoushiManga]
    public let hasNextPage: Bool
}

public extension JVMRuntime {
    @discardableResult
    func initializeExtensionCompatibility() throws -> ExtensionHostResponse {
        try checkedDispatch(
            ExtensionHostRequest(operation: "initializeCompatibility")
        )
    }

    @discardableResult
    func loadKeiyoushiExtension(
        id: String,
        jarURL: URL,
        entryClass: String? = nil
    ) throws -> ExtensionHostResponse {
        try checkedDispatch(
            ExtensionHostRequest(
                operation: "loadExtension",
                extensionId: id,
                jarPath: jarURL.path,
                entryClass: entryClass
            )
        )
    }

    func popularManga(
        extensionId: String,
        page: Int
    ) throws -> KeiyoushiMangaPage {
        guard page > 0 else {
            throw JVMRuntimeError.invalidConfiguration(
                "Popular manga page must be at least 1"
            )
        }
        let response = try checkedDispatch(
            ExtensionHostRequest(
                operation: "getPopularManga",
                extensionId: extensionId,
                argument: String(page)
            )
        )
        guard let result = response.result else {
            throw JVMRuntimeError.decodingFailed(
                "Popular manga response has no result"
            )
        }
        do {
            return try JSONDecoder().decode(
                KeiyoushiMangaPage.self,
                from: Data(result.utf8)
            )
        } catch {
            throw JVMRuntimeError.decodingFailed(
                error.localizedDescription
            )
        }
    }

    private func checkedDispatch(
        _ request: ExtensionHostRequest
    ) throws -> ExtensionHostResponse {
        let response: ExtensionHostResponse = try dispatch(request)
        guard response.success else {
            throw JVMRuntimeError.dispatchFailed(
                status: -1,
                message: response.error ?? "Unknown extension host error"
            )
        }
        return response
    }
}
