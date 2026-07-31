import CryptoKit
import AidokuRunner
import Foundation
import TachiJVMRunner

actor JVMSourceRuntime {
    static let shared = JVMSourceRuntime()

    enum RuntimeError: LocalizedError {
        case missingBundleResource(String)
        case checksumMismatch(expected: String, actual: String)
        case invalidExtensionIdentifier
        case extensionIdentityMismatch(expected: String, actual: String)
        case hostRejected(String)

        var errorDescription: String? {
            switch self {
                case .missingBundleResource(let name):
                    "The bundled JVM resource is missing: \(name)"
                case .checksumMismatch(let expected, let actual):
                    "Extension checksum mismatch. Expected \(expected), got \(actual)."
                case .invalidExtensionIdentifier:
                    "The extension identifier is invalid."
                case .extensionIdentityMismatch(let expected, let actual):
                    "Expected extension \(expected), got \(actual)."
                case .hostRejected(let message):
                    "The Java extension host rejected the request: \(message)"
            }
        }
    }

    private let fileManager: FileManager
    private var runtime: JVMRuntime?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func ping() async throws -> ExtensionHostResponse {
        try await dispatch(.init(operation: "ping"))
    }

    func inspect(jar: URL) async throws -> JVMExtensionInspection {
        let secured = jar.startAccessingSecurityScopedResource()
        defer {
            if secured {
                jar.stopAccessingSecurityScopedResource()
            }
        }
        let response = try await dispatch(
            .init(operation: "inspectExtension", jarPath: jar.path)
        )
        return try JVMExtensionInspection(response: response)
    }

    @discardableResult
    func install(
        jar sourceJar: URL,
        manifest: JVMExtensionManifest
    ) async throws -> URL {
        guard !manifest.directoryName.isEmpty else {
            throw RuntimeError.invalidExtensionIdentifier
        }

        let secured = sourceJar.startAccessingSecurityScopedResource()
        defer {
            if secured {
                sourceJar.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: sourceJar, options: .mappedIfSafe)
        let checksum = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard checksum.caseInsensitiveCompare(manifest.sha256) == .orderedSame else {
            throw RuntimeError.checksumMismatch(
                expected: manifest.sha256,
                actual: checksum
            )
        }

        let directory = try extensionDirectory(for: manifest)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let jar = directory.appendingPathComponent(
            "extension.jar",
            isDirectory: false
        )
        let metadata = directory.appendingPathComponent(
            "manifest.json",
            isDirectory: false
        )

        if fileManager.fileExists(atPath: jar.path) {
            try fileManager.removeItem(at: jar)
        }
        try fileManager.copyItem(at: sourceJar, to: jar)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: metadata,
            options: .atomic
        )

        let response = try await dispatch(
            .init(
                operation: "loadExtension",
                extensionId: manifest.id,
                jarPath: jar.path,
                entryClass: manifest.entryClass
            )
        )
        try requireSuccess(response)
        return jar
    }

    @discardableResult
    func install(
        catalogEntry: KeiyoushiJarRepository.Catalog.Extension,
        using session: URLSession = .shared
    ) async throws -> JVMExtensionManifest {
        let (temporaryJar, response) = try await session.download(
            from: catalogEntry.resources.jarUrl
        )
        if
            let httpResponse = response as? HTTPURLResponse,
            !(200..<300).contains(httpResponse.statusCode)
        {
            throw URLError(.badServerResponse)
        }
        let inspection = try await inspect(jar: temporaryJar)
        guard inspection.packageName == catalogEntry.packageName else {
            throw RuntimeError.extensionIdentityMismatch(
                expected: catalogEntry.packageName,
                actual: inspection.packageName
            )
        }
        guard inspection.version == catalogEntry.versionName else {
            throw RuntimeError.extensionIdentityMismatch(
                expected: catalogEntry.versionName,
                actual: inspection.version
            )
        }
        let data = try Data(contentsOf: temporaryJar, options: .mappedIfSafe)
        let sha256 = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        let manifest = JVMExtensionManifest(
            inspection: inspection,
            sourceURL: catalogEntry.resources.jarUrl,
            sha256: sha256
        )
        try await install(jar: temporaryJar, manifest: manifest)
        return manifest
    }

    func loadInstalled(_ manifest: JVMExtensionManifest) async throws {
        let jar = try extensionDirectory(for: manifest)
            .appendingPathComponent("extension.jar")
        let response = try await dispatch(
            .init(
                operation: "loadExtension",
                extensionId: manifest.id,
                jarPath: jar.path,
                entryClass: manifest.entryClass
            )
        )
        try requireSuccess(response)
    }

    func installedManifests() throws -> [JVMExtensionManifest] {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = applicationSupport.appendingPathComponent(
            "JVMExtensions",
            isDirectory: true
        )
        guard fileManager.fileExists(atPath: root.path) else {
            return []
        }

        let packageDirectories = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var manifestsById: [String: JVMExtensionManifest] = [:]
        for packageDirectory in packageDirectories {
            let versions = try fileManager.contentsOfDirectory(
                at: packageDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for versionDirectory in versions {
                let metadata = versionDirectory.appendingPathComponent(
                    "manifest.json",
                    isDirectory: false
                )
                guard
                    let data = try? Data(contentsOf: metadata),
                    let manifest = try? JSONDecoder().decode(
                        JVMExtensionManifest.self,
                        from: data
                    )
                else {
                    continue
                }
                if
                    let current = manifestsById[manifest.id],
                    current.version.compare(
                        manifest.version,
                        options: .numeric
                    ) != .orderedAscending
                {
                    continue
                }
                manifestsById[manifest.id] = manifest
            }
        }
        return manifestsById.values.sorted { $0.name < $1.name }
    }

    func installedAidokuSources() async -> [AidokuRunner.Source] {
        guard let manifests = try? installedManifests() else {
            return []
        }
        var result: [AidokuRunner.Source] = []
        for manifest in manifests {
            do {
                try await loadInstalled(manifest)
                let descriptors = try await sources(
                    extensionId: manifest.id
                )
                result.append(contentsOf: descriptors.map {
                    .keiyoushi(
                        manifest: manifest,
                        descriptor: $0
                    )
                })
            } catch {
                LogManager.logger.error(
                    "Failed to load JVM extension \(manifest.id): \(error)"
                )
            }
        }
        return result
    }

    func invoke(
        extensionId: String,
        method: String,
        argument: String? = nil
    ) async throws -> String? {
        let response = try await dispatch(
            .init(
                operation: "invoke",
                extensionId: extensionId,
                method: method,
                argument: argument
            )
        )
        try requireSuccess(response)
        return response.result
    }

    func popularManga(
        extensionId: String,
        sourceId: Int64? = nil,
        page: Int
    ) async throws -> KeiyoushiMangaPage {
        try await pagedManga(
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
    ) async throws -> KeiyoushiMangaPage {
        try await pagedManga(
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
    ) async throws -> KeiyoushiMangaPage {
        guard !query.isEmpty else {
            throw RuntimeError.hostRejected(
                "Search query must not be empty."
            )
        }
        return try await pagedManga(
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
    ) async throws -> KeiyoushiMangaPage {
        guard page > 0 else {
            throw RuntimeError.hostRejected(
                "Manga page must be at least 1."
            )
        }
        let response = try await dispatch(
            .init(
                operation: operation,
                extensionId: extensionId,
                sourceId: sourceId.map(String.init),
                argument: String(page),
                query: query
            )
        )
        try requireSuccess(response)
        guard let result = response.result else {
            throw RuntimeError.hostRejected(
                "The manga-page operation returned no payload."
            )
        }
        do {
            return try JSONDecoder().decode(
                KeiyoushiMangaPage.self,
                from: Data(result.utf8)
            )
        } catch {
            throw RuntimeError.hostRejected(
                "Unable to decode the manga page: \(error.localizedDescription)"
            )
        }
    }

    func sources(
        extensionId: String
    ) async throws -> [KeiyoushiSourceDescriptor] {
        let response = try await dispatch(
            .init(
                operation: "listSources",
                extensionId: extensionId
            )
        )
        try requireSuccess(response)
        guard let result = response.result else {
            throw RuntimeError.hostRejected(
                "The source-list operation returned no payload."
            )
        }
        do {
            return try JSONDecoder().decode(
                [KeiyoushiSourceDescriptor].self,
                from: Data(result.utf8)
            )
        } catch {
            throw RuntimeError.hostRejected(
                "Unable to decode the source list: \(error.localizedDescription)"
            )
        }
    }

    func mangaUpdate(
        extensionId: String,
        sourceId: Int64? = nil,
        mangaURL: String,
        mangaTitle: String
    ) async throws -> KeiyoushiMangaUpdate {
        let response = try await dispatch(
            .init(
                operation: "getMangaUpdate",
                extensionId: extensionId,
                sourceId: sourceId.map(String.init),
                mangaURL: mangaURL,
                mangaTitle: mangaTitle
            )
        )
        try requireSuccess(response)
        return try decodeResult(response, as: KeiyoushiMangaUpdate.self)
    }

    func pages(
        extensionId: String,
        sourceId: Int64? = nil,
        chapterURL: String,
        chapterName: String
    ) async throws -> [KeiyoushiPage] {
        let response = try await dispatch(
            .init(
                operation: "getPageList",
                extensionId: extensionId,
                sourceId: sourceId.map(String.init),
                chapterURL: chapterURL,
                chapterName: chapterName
            )
        )
        try requireSuccess(response)
        return try decodeResult(response, as: [KeiyoushiPage].self)
    }

    private func decodeResult<Value: Decodable>(
        _ response: ExtensionHostResponse,
        as type: Value.Type
    ) throws -> Value {
        guard let result = response.result else {
            throw RuntimeError.hostRejected(
                "The extension operation returned no payload."
            )
        }
        do {
            return try JSONDecoder().decode(
                type,
                from: Data(result.utf8)
            )
        } catch {
            throw RuntimeError.hostRejected(
                "Unable to decode the extension payload: \(error.localizedDescription)"
            )
        }
    }

    func unload(extensionId: String) async throws {
        let response = try await dispatch(
            .init(
                operation: "unloadExtension",
                extensionId: extensionId
            )
        )
        try requireSuccess(response)
    }

    func uninstall(extensionId: String) async throws {
        if runtime != nil {
            try await unload(extensionId: extensionId)
        }
        guard
            let manifest = try installedManifests().first(
                where: { $0.id == extensionId }
            )
        else {
            return
        }
        let packageDirectory = try extensionDirectory(for: manifest)
            .deletingLastPathComponent()
        if fileManager.fileExists(atPath: packageDirectory.path) {
            try fileManager.removeItem(at: packageDirectory)
        }
    }

    func decodeMihonBackup(at url: URL) async throws -> Data {
        let secured = url.startAccessingSecurityScopedResource()
        defer {
            if secured {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let response = try await dispatch(
            .init(
                operation: "decodeBackup",
                backupPath: url.path
            )
        )
        try requireSuccess(response)
        guard let result = response.result else {
            throw RuntimeError.hostRejected(
                "The backup decoder returned no payload."
            )
        }
        return Data(result.utf8)
    }

    private func dispatch(
        _ request: ExtensionHostRequest
    ) async throws -> ExtensionHostResponse {
        let activeRuntime: JVMRuntime
        if let runtime {
            activeRuntime = runtime
        } else {
            activeRuntime = try makeRuntime()
            self.runtime = activeRuntime
        }
        return try await activeRuntime.dispatch(
            request,
            as: ExtensionHostResponse.self
        )
    }

    private func makeRuntime() throws -> JVMRuntime {
        return try JVMRuntime(
            configuration: .bundled(in: .main)
        )
    }

    private func extensionDirectory(
        for manifest: JVMExtensionManifest
    ) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport
            .appendingPathComponent("JVMExtensions", isDirectory: true)
            .appendingPathComponent(manifest.directoryName, isDirectory: true)
            .appendingPathComponent(manifest.version, isDirectory: true)
    }

    private func requireSuccess(
        _ response: ExtensionHostResponse
    ) throws {
        if !response.success {
            throw RuntimeError.hostRejected(
                response.error ?? "Unknown Java error"
            )
        }
    }
}

private extension AidokuRunner.Source {
    static func keiyoushi(
        manifest: JVMExtensionManifest,
        descriptor: KeiyoushiSourceDescriptor
    ) -> AidokuRunner.Source {
        var listings = [
            AidokuRunner.Listing(
                id: "popular",
                name: NSLocalizedString("POPULAR")
            )
        ]
        if descriptor.supportsLatest {
            listings.append(
                AidokuRunner.Listing(
                    id: "latest",
                    name: NSLocalizedString("LATEST")
                )
            )
        }
        return .init(
            url: nil,
            key: KeiyoushiSourceRunner.key(for: descriptor.id),
            name: descriptor.name,
            version: 1,
            languages: [descriptor.lang],
            urls: [],
            contentRating: .safe,
            config: .init(
                languageSelectType: .single,
                supportsTagSearch: true
            ),
            staticListings: listings,
            staticFilters: [],
            staticSettings: [],
            runner: KeiyoushiSourceRunner(
                extensionId: manifest.id,
                descriptor: descriptor
            )
        )
    }
}

actor KeiyoushiSourceRunner: AidokuRunner.Runner {
    let features = AidokuRunner.SourceFeatures(
        providesListings: true
    )

    nonisolated let extensionId: String
    private let descriptor: KeiyoushiSourceDescriptor
    private let sourceKey: String

    init(
        extensionId: String,
        descriptor: KeiyoushiSourceDescriptor
    ) {
        self.extensionId = extensionId
        self.descriptor = descriptor
        sourceKey = Self.key(for: descriptor.id)
    }

    nonisolated static func key(for sourceId: Int64) -> String {
        "mihon.\(sourceId)"
    }

    func uninstall() async throws {
        try await JVMSourceRuntime.shared.uninstall(
            extensionId: extensionId
        )
    }

    func getSearchMangaList(
        query: String?,
        page: Int,
        filters: [AidokuRunner.FilterValue]
    ) async throws -> AidokuRunner.MangaPageResult {
        let result: KeiyoushiMangaPage
        if let query, !query.isEmpty {
            result = try await JVMSourceRuntime.shared.searchManga(
                extensionId: extensionId,
                sourceId: descriptor.id,
                query: query,
                page: page
            )
        } else {
            result = try await JVMSourceRuntime.shared.popularManga(
                extensionId: extensionId,
                sourceId: descriptor.id,
                page: page
            )
        }
        return result.intoAidoku(sourceKey: sourceKey)
    }

    func getMangaList(
        listing: AidokuRunner.Listing,
        page: Int
    ) async throws -> AidokuRunner.MangaPageResult {
        let result = if listing.id == "latest" {
            try await JVMSourceRuntime.shared.latestManga(
                extensionId: extensionId,
                sourceId: descriptor.id,
                page: page
            )
        } else {
            try await JVMSourceRuntime.shared.popularManga(
                extensionId: extensionId,
                sourceId: descriptor.id,
                page: page
            )
        }
        return result.intoAidoku(sourceKey: sourceKey)
    }

    func getMangaUpdate(
        manga: AidokuRunner.Manga,
        needsDetails: Bool,
        needsChapters: Bool
    ) async throws -> AidokuRunner.Manga {
        let result = try await JVMSourceRuntime.shared.mangaUpdate(
            extensionId: extensionId,
            sourceId: descriptor.id,
            mangaURL: manga.key,
            mangaTitle: manga.title
        )
        var updated = manga
        if needsDetails {
            updated = manga.copy(
                from: result.manga.intoAidoku(sourceKey: sourceKey)
            )
        }
        if needsChapters {
            updated.chapters = result.chapters.map(\.intoAidoku)
        }
        return updated
    }

    func getPageList(
        manga: AidokuRunner.Manga,
        chapter: AidokuRunner.Chapter
    ) async throws -> [AidokuRunner.Page] {
        let pages = try await JVMSourceRuntime.shared.pages(
            extensionId: extensionId,
            sourceId: descriptor.id,
            chapterURL: chapter.key,
            chapterName: chapter.title ?? ""
        )
        return try pages.map(\.intoAidoku)
    }
}

private extension KeiyoushiMangaPage {
    func intoAidoku(sourceKey: String) -> AidokuRunner.MangaPageResult {
        .init(
            entries: mangas.map { $0.intoAidoku(sourceKey: sourceKey) },
            hasNextPage: hasNextPage
        )
    }
}

private extension KeiyoushiManga {
    func intoAidoku(sourceKey: String) -> AidokuRunner.Manga {
        let publishingStatus: AidokuRunner.PublishingStatus = switch status {
            case 1: .ongoing
            case 2, 4: .completed
            case 5: .cancelled
            case 6: .hiatus
            default: .unknown
        }
        return .init(
            sourceKey: sourceKey,
            key: url,
            title: title,
            cover: thumbnailURL,
            artists: artist.map { [$0] },
            authors: author.map { [$0] },
            description: description,
            url: URL(string: url),
            tags: genre?
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? [],
            status: publishingStatus
        )
    }
}

private extension KeiyoushiChapter {
    var intoAidoku: AidokuRunner.Chapter {
        .init(
            key: url,
            title: name.isEmpty ? nil : name,
            chapterNumber: chapterNumber,
            dateUploaded: dateUpload > 0
                ? Date(timeIntervalSince1970: Double(dateUpload) / 1_000)
                : nil,
            scanlators: scanlator.flatMap {
                $0.isEmpty ? nil : [$0]
            },
            url: URL(string: url)
        )
    }
}

private extension KeiyoushiPage {
    var intoAidoku: AidokuRunner.Page {
        get throws {
            let candidates = [imageURL, uri, url.isEmpty ? nil : url]
            guard
                let value = candidates.compactMap({ $0 }).first,
                let resolvedURL = URL(string: value)
            else {
                throw SourceError.message("INVALID_PAGE_URL")
            }
            return .init(content: .url(url: resolvedURL))
        }
    }
}
