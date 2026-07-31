import Foundation

enum KeiyoushiJarRepository {
    struct Catalog: Decodable, Sendable {
        let name: String
        let extensionList: ExtensionList

        struct ExtensionList: Decodable, Sendable {
            let extensions: [Extension]
        }

        struct Extension: Decodable, Identifiable, Sendable {
            let name: String
            let packageName: String
            let resources: Resources
            let extensionLib: String
            let versionCode: String
            let versionName: String
            let contentWarning: String?
            let sources: [Source]

            var id: String { packageName }
            var isNsfw: Bool {
                contentWarning == "CONTENT_WARNING_NSFW"
            }

            var usesSupportedExtensionLibrary: Bool {
                let components = extensionLib.split(separator: ".")
                guard
                    components.count >= 2,
                    components[0] == "1",
                    let minor = Int(components[1])
                else {
                    return false
                }
                return (4...6).contains(minor)
            }
        }

        struct Resources: Decodable, Sendable {
            let apkUrl: URL
            let iconUrl: URL?
            let jarUrl: URL
        }

        struct Source: Decodable, Identifiable, Sendable {
            let id: String
            let name: String
            let language: String
            let homeUrl: URL?
        }
    }

    struct Artifact: Hashable, Sendable {
        let fileName: String
        let sha256: String?

        var url: URL {
            KeiyoushiJarRepository.repositoryRoot
                .appendingPathComponent(fileName, isDirectory: false)
        }
    }

    enum RepositoryError: LocalizedError {
        case invalidArtifactName(String)

        var errorDescription: String? {
            switch self {
                case .invalidArtifactName(let name):
                    "Invalid Keiyoushi JAR artifact name: \(name)"
            }
        }
    }

    static let repositoryRoot = URL(
        string: "https://raw.githubusercontent.com/keiyoushi/extensions/repo/jar/"
    )!
    static let catalogURL = URL(
        string: "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.json"
    )!

    /// Pinned real-world compatibility fixture used by the host test script.
    static let asuraScansFixture = Artifact(
        fileName: "tachiyomi-en.asurascans-v1.6.66.jar",
        sha256: "ce8d03b408a6b329b02f9b2c9280badb981ff352703a45749a443f87805c46ff"
    )

    /// Keiyoushi's JAR directory mirrors the index artifact basename, changing
    /// only the final `.apk` suffix to `.jar`.
    static func artifact(fromIndexFileName name: String) throws -> Artifact {
        guard
            name.hasSuffix(".apk"),
            !name.contains("/"),
            !name.contains("\\"),
            name != ".apk"
        else {
            throw RepositoryError.invalidArtifactName(name)
        }
        return Artifact(
            fileName: String(name.dropLast(4)) + ".jar",
            sha256: nil
        )
    }

    static func fetchCatalog(
        using session: URLSession = .shared
    ) async throws -> Catalog {
        var request = URLRequest(url: catalogURL)
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        if
            let httpResponse = response as? HTTPURLResponse,
            !(200..<300).contains(httpResponse.statusCode)
        {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Catalog.self, from: data)
    }
}
