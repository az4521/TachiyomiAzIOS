import CryptoKit
import Foundation
import TachiJVMRunner

actor JVMSourceRuntime {
    static let shared = JVMSourceRuntime()

    enum RuntimeError: LocalizedError {
        case missingBundleResource(String)
        case checksumMismatch(expected: String, actual: String)
        case invalidExtensionIdentifier
        case hostRejected(String)

        var errorDescription: String? {
            switch self {
                case .missingBundleResource(let name):
                    "The bundled JVM resource is missing: \(name)"
                case .checksumMismatch(let expected, let actual):
                    "Extension checksum mismatch. Expected \(expected), got \(actual)."
                case .invalidExtensionIdentifier:
                    "The extension identifier is invalid."
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
        guard page > 0 else {
            throw RuntimeError.hostRejected(
                "Popular manga page must be at least 1."
            )
        }
        let response = try await dispatch(
            .init(
                operation: "getPopularManga",
                extensionId: extensionId,
                sourceId: sourceId.map(String.init),
                argument: String(page)
            )
        )
        try requireSuccess(response)
        guard let result = response.result else {
            throw RuntimeError.hostRejected(
                "The popular manga operation returned no payload."
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

    func unload(extensionId: String) async throws {
        let response = try await dispatch(
            .init(
                operation: "unloadExtension",
                extensionId: extensionId
            )
        )
        try requireSuccess(response)
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
