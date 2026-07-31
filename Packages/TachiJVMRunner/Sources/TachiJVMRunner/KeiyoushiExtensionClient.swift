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

public struct KeiyoushiChapter: Codable, Sendable, Equatable {
    public let url: String
    public let name: String
    public let chapterNumber: Float
    public let scanlator: String?
    public let dateUpload: Int64
}

public struct KeiyoushiMangaUpdate: Codable, Sendable, Equatable {
    public let manga: KeiyoushiManga
    public let chapters: [KeiyoushiChapter]
}

public struct KeiyoushiPage: Codable, Sendable, Equatable {
    public let index: Int
    public let url: String
    public let imageURL: String?
    public let uri: String?
}

public struct KeiyoushiSourceDescriptor: Codable, Sendable, Equatable {
    public let id: Int64
    public let name: String
    public let lang: String
    public let supportsLatest: Bool
    public let baseURL: String?

    public init(
        id: Int64,
        name: String,
        lang: String,
        supportsLatest: Bool,
        baseURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.lang = lang
        self.supportsLatest = supportsLatest
        self.baseURL = baseURL
    }
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
        sourceId: Int64? = nil,
        page: Int
    ) throws -> KeiyoushiMangaPage {
        try pagedManga(
            operation: "getPopularManga",
            extensionId: extensionId,
            sourceId: sourceId,
            page: page
        )
    }

    func latestManga(
        extensionId: String,
        sourceId: Int64? = nil,
        page: Int
    ) throws -> KeiyoushiMangaPage {
        try pagedManga(
            operation: "getLatestUpdates",
            extensionId: extensionId,
            sourceId: sourceId,
            page: page
        )
    }

    func searchManga(
        extensionId: String,
        sourceId: Int64? = nil,
        query: String,
        page: Int
    ) throws -> KeiyoushiMangaPage {
        guard !query.isEmpty else {
            throw JVMRuntimeError.invalidConfiguration(
                "Search query must not be empty"
            )
        }
        return try pagedManga(
            operation: "searchManga",
            extensionId: extensionId,
            sourceId: sourceId,
            page: page,
            query: query
        )
    }

    private func pagedManga(
        operation: String,
        extensionId: String,
        sourceId: Int64?,
        page: Int,
        query: String? = nil
    ) throws -> KeiyoushiMangaPage {
        guard page > 0 else {
            throw JVMRuntimeError.invalidConfiguration(
                "Manga page must be at least 1"
            )
        }
        let response = try checkedDispatch(
            ExtensionHostRequest(
                operation: operation,
                extensionId: extensionId,
                sourceId: sourceId.map(String.init),
                argument: String(page),
                query: query
            )
        )
        guard let result = response.result else {
            throw JVMRuntimeError.decodingFailed(
                "Manga-page response has no result"
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

    func sources(
        extensionId: String
    ) throws -> [KeiyoushiSourceDescriptor] {
        let response = try checkedDispatch(
            ExtensionHostRequest(
                operation: "listSources",
                extensionId: extensionId
            )
        )
        guard let result = response.result else {
            throw JVMRuntimeError.decodingFailed(
                "Source list response has no result"
            )
        }
        do {
            return try JSONDecoder().decode(
                [KeiyoushiSourceDescriptor].self,
                from: Data(result.utf8)
            )
        } catch {
            throw JVMRuntimeError.decodingFailed(
                error.localizedDescription
            )
        }
    }

    func mangaUpdate(
        extensionId: String,
        sourceId: Int64? = nil,
        mangaURL: String,
        mangaTitle: String
    ) throws -> KeiyoushiMangaUpdate {
        let response = try checkedDispatch(
            ExtensionHostRequest(
                operation: "getMangaUpdate",
                extensionId: extensionId,
                sourceId: sourceId.map(String.init),
                mangaURL: mangaURL,
                mangaTitle: mangaTitle
            )
        )
        return try decodeResult(response, as: KeiyoushiMangaUpdate.self)
    }

    func pages(
        extensionId: String,
        sourceId: Int64? = nil,
        chapterURL: String,
        chapterName: String
    ) throws -> [KeiyoushiPage] {
        let response = try checkedDispatch(
            ExtensionHostRequest(
                operation: "getPageList",
                extensionId: extensionId,
                sourceId: sourceId.map(String.init),
                chapterURL: chapterURL,
                chapterName: chapterName
            )
        )
        return try decodeResult(response, as: [KeiyoushiPage].self)
    }

    private func decodeResult<Value: Decodable>(
        _ response: ExtensionHostResponse,
        as type: Value.Type
    ) throws -> Value {
        guard let result = response.result else {
            throw JVMRuntimeError.decodingFailed(
                "Extension response has no result"
            )
        }
        do {
            return try JSONDecoder().decode(
                type,
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
