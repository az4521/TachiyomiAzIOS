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
            sha256: sha256,
            versionCode: catalogEntry.versionCode,
            extensionLibrary: catalogEntry.extensionLib,
            isNsfw: catalogEntry.isNsfw
        )
        try await install(jar: temporaryJar, manifest: manifest)
        try removeSupersededVersions(of: manifest)
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
        page: Int,
        filters: [AidokuRunner.FilterValue] = []
    ) async throws -> KeiyoushiMangaPage {
        return try await pagedManga(
            operation: "searchManga",
            extensionId: extensionId,
            sourceId: sourceId,
            page: page,
            query: query,
            filterStates: Self.encode(filters: filters)
        )
    }

    func searchFilters(
        extensionId: String,
        sourceId: Int64
    ) async throws -> [KeiyoushiFilterDescriptor] {
        try await decodedResult(
            .init(
                operation: "getSearchFilters",
                extensionId: extensionId,
                sourceId: String(sourceId)
            ),
            as: [KeiyoushiFilterDescriptor].self
        )
    }

    func settings(
        extensionId: String,
        sourceId: Int64
    ) async throws -> [KeiyoushiSettingDescriptor] {
        try await decodedResult(
            .init(
                operation: "getSettings",
                extensionId: extensionId,
                sourceId: String(sourceId)
            ),
            as: [KeiyoushiSettingDescriptor].self
        )
    }

    func setSetting(
        extensionId: String,
        sourceId: Int64,
        key: String,
        type: String,
        value: String
    ) async throws {
        let response = try await dispatch(
            .init(
                operation: "setSetting",
                extensionId: extensionId,
                sourceId: String(sourceId),
                settingKey: key,
                settingType: type,
                settingValue: value
            )
        )
        try requireSuccess(response)
    }

    private func pagedManga(
        operation: String,
        extensionId: String,
        sourceId: Int64?,
        page: Int,
        query: String? = nil,
        filterStates: String? = nil
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
                query: query,
                filterStates: filterStates
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

    private nonisolated static func encode(
        filters: [AidokuRunner.FilterValue]
    ) -> String? {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._~")
        )
        let lines = filters.compactMap { filter -> String? in
            let id: String
            let kind: String
            let value: String
            let auxiliary: String?
            switch filter {
                case .text(let filterId, let text):
                    (id, kind, value, auxiliary) = (
                        filterId,
                        "text",
                        text,
                        nil
                    )
                case .check(let filterId, let state):
                    (id, kind, value, auxiliary) = (
                        filterId,
                        "check",
                        String(state),
                        nil
                    )
                case .select(let filterId, let selected):
                    (id, kind, value, auxiliary) = (
                        filterId,
                        "select",
                        selected,
                        nil
                    )
                case .sort(let selection):
                    (id, kind, value, auxiliary) = (
                        selection.id,
                        "sort",
                        String(selection.index),
                        String(selection.ascending)
                    )
                case .multiselect, .range:
                    return nil
            }
            let escaped = value.addingPercentEncoding(
                withAllowedCharacters: allowed
            ) ?? ""
            return [id, kind, escaped, auxiliary]
                .compactMap { $0 }
                .joined(separator: "\t")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
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

    func imageRequest(
        extensionId: String,
        sourceId: Int64,
        imageURL: String,
        pageURL: String?
    ) async throws -> KeiyoushiImageRequest {
        try await decodedResult(
            .init(
                operation: "getImageRequest",
                extensionId: extensionId,
                sourceId: String(sourceId),
                imageURL: imageURL,
                pageURL: pageURL
            ),
            as: KeiyoushiImageRequest.self
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

    private func removeSupersededVersions(
        of manifest: JVMExtensionManifest
    ) throws {
        let installed = try extensionDirectory(for: manifest)
        let packageDirectory = installed.deletingLastPathComponent()
        for directory in try fileManager.contentsOfDirectory(
            at: packageDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) where directory.lastPathComponent != installed.lastPathComponent {
            try fileManager.removeItem(at: directory)
        }
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
            version: Int(manifest.versionCode ?? "") ?? 1,
            languages: [descriptor.lang],
            urls: [],
            contentRating:
                manifest.isNsfw == true ? .primarilyNsfw : .safe,
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
        providesListings: true,
        dynamicFilters: true,
        dynamicSettings: true,
        providesImageRequests: true,
        handlesNotifications: true
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
                page: page,
                filters: filters
            )
        } else if !filters.isEmpty {
            result = try await JVMSourceRuntime.shared.searchManga(
                extensionId: extensionId,
                sourceId: descriptor.id,
                query: "",
                page: page,
                filters: filters
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

    func getSearchFilters() async throws -> [AidokuRunner.Filter] {
        try await JVMSourceRuntime.shared.searchFilters(
            extensionId: extensionId,
            sourceId: descriptor.id
        ).map(\.intoAidoku)
    }

    func getSettings() async throws -> [AidokuRunner.Setting] {
        let settings = try await JVMSourceRuntime.shared.settings(
            extensionId: extensionId,
            sourceId: descriptor.id
        )
        let items = settings.map {
            $0.intoAidoku(sourceKey: sourceKey)
        }
        guard !items.isEmpty else {
            return []
        }
        return [
            .init(
                value: .group(.init(items: items))
            )
        ]
    }

    func handleNotification(notification: String) async throws {
        let prefix = "keiyoushi-setting:"
        guard notification.hasPrefix(prefix) else {
            return
        }
        let key = String(notification.dropFirst(prefix.count))
        let settings = try await JVMSourceRuntime.shared.settings(
            extensionId: extensionId,
            sourceId: descriptor.id
        )
        guard let setting = settings.first(where: { $0.key == key }) else {
            return
        }
        let storedKey = "\(sourceKey).\(key)"
        let value: String = switch setting.type {
            case "toggle":
                String(UserDefaults.standard.bool(forKey: storedKey))
            case "multiselect":
                (UserDefaults.standard.stringArray(forKey: storedKey) ?? [])
                    .joined(separator: "\n")
            default:
                UserDefaults.standard.string(forKey: storedKey) ?? ""
        }
        try await JVMSourceRuntime.shared.setSetting(
            extensionId: extensionId,
            sourceId: descriptor.id,
            key: key,
            type: setting.type,
            value: value
        )
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

    func getImageRequest(
        url: String,
        context: AidokuRunner.PageContext?
    ) async throws -> URLRequest {
        do {
            let descriptor = try await JVMSourceRuntime.shared.imageRequest(
                extensionId: extensionId,
                sourceId: self.descriptor.id,
                imageURL: url,
                pageURL: context?["mihonPageURL"]
            )
            var request = URLRequest(url: descriptor.url)
            for (name, value) in descriptor.headers {
                request.setValue(value, forHTTPHeaderField: name)
            }
            return request
        } catch {
            guard let url = URL(string: url) else {
                throw error
            }
            return URLRequest(url: url)
        }
    }
}

struct KeiyoushiFilterDescriptor: Decodable, Sendable {
    let id: String
    let type: String
    let name: String
    let options: [String]?
    let defaultValue: String?
    let auxiliary: String?

    var intoAidoku: AidokuRunner.Filter {
        let value = switch type {
            case "text":
                AidokuRunner.Filter(
                    id: id,
                    title: name,
                    value: .text(placeholder: nil)
                )
            case "check":
                AidokuRunner.Filter(
                    id: id,
                    title: name,
                    value: .check(
                        name: nil,
                        canExclude: auxiliary == "true",
                        defaultValue: defaultState
                    )
                )
            case "select":
                AidokuRunner.Filter(
                    id: id,
                    title: name,
                    value: .select(.init(
                        options: options ?? [],
                        ids: (options ?? []).indices.map(String.init),
                        defaultValue: defaultValue
                    ))
                )
            case "sort":
                AidokuRunner.Filter(
                    id: id,
                    title: name,
                    value: .sort(
                        canAscend: true,
                        options: options ?? [],
                        defaultValue: defaultValue
                            .flatMap(Int.init)
                            .map {
                                .init(
                                    index: $0,
                                    ascending: auxiliary == "true"
                                )
                            }
                    )
                )
            default:
                AidokuRunner.Filter(
                    id: id,
                    title: nil,
                    value: .note(name)
                )
        }
        return value
    }

    private var defaultState: Bool? {
        switch defaultValue {
            case "true", "1": true
            case "false", "0": false
            case .some: nil
            case .none: nil
        }
    }
}

struct KeiyoushiSettingDescriptor: Decodable, Sendable {
    let key: String
    let title: String?
    let summary: String?
    let type: String
    let enabled: Bool
    let currentValue: String?
    let options: [String]?
    let values: [String]?

    func intoAidoku(sourceKey: String) -> AidokuRunner.Setting {
        seedCurrentValue(sourceKey: sourceKey)
        let notification = "keiyoushi-setting:\(key)"
        switch type {
            case "toggle":
                return .init(
                    key: key,
                    title: title ?? key,
                    notification: notification,
                    refreshes: ["content", "listings", "filters", "settings"],
                    value: .toggle(.init(subtitle: summary))
                )
            case "select":
                return .init(
                    key: key,
                    title: title ?? key,
                    notification: notification,
                    refreshes: ["content", "listings", "filters", "settings"],
                    value: .select(.init(
                        values: values ?? [],
                        titles: options ?? []
                    ))
                )
            case "multiselect":
                return .init(
                    key: key,
                    title: title ?? key,
                    notification: notification,
                    refreshes: ["content", "listings", "filters", "settings"],
                    value: .multiselect(.init(
                        values: values ?? [],
                        titles: options ?? []
                    ))
                )
            default:
                return .init(
                    key: key,
                    title: title ?? key,
                    notification: notification,
                    refreshes: ["content", "listings", "filters", "settings"],
                    value: .text(.init(
                        placeholder: summary,
                        autocorrectionDisabled: true,
                        defaultValue: currentValue
                    ))
                )
        }
    }

    private func seedCurrentValue(sourceKey: String) {
        let defaults = UserDefaults.standard
        let namespacedKey = "\(sourceKey).\(key)"
        guard defaults.object(forKey: namespacedKey) == nil else {
            return
        }
        switch type {
            case "toggle":
                defaults.set(currentValue == "true", forKey: namespacedKey)
            case "multiselect":
                defaults.set(
                    currentValue?.components(separatedBy: "\n") ?? [],
                    forKey: namespacedKey
                )
            default:
                defaults.set(currentValue ?? "", forKey: namespacedKey)
        }
    }
}

struct KeiyoushiImageRequest: Decodable, Sendable {
    let url: URL
    let headers: [String: String]
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
            let context = url.isEmpty
                ? nil
                : ["mihonPageURL": url]
            return .init(
                content: .url(url: resolvedURL, context: context)
            )
        }
    }
}
