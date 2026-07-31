import Foundation

enum KeiyoushiJarRepository {
    struct Repository: Codable, Identifiable, Sendable, Hashable {
        let name: String
        let catalogURL: URL

        var id: String { catalogURL.absoluteString }
    }

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

    enum RepositoryError: LocalizedError {
        case invalidURL
        case unsupportedScheme

        var errorDescription: String? {
            switch self {
                case .invalidURL:
                    "Enter a valid extension repository URL."
                case .unsupportedScheme:
                    "Extension repository URLs must use HTTP or HTTPS."
            }
        }
    }

    private static let defaultsKey = "extensionRepositories"

    static func repositories(
        defaults: UserDefaults = .standard
    ) -> [Repository] {
        guard
            let data = defaults.data(forKey: defaultsKey),
            let repositories = try? JSONDecoder().decode(
                [Repository].self,
                from: data
            )
        else {
            return []
        }
        return repositories
    }

    static func save(
        repositories: [Repository],
        defaults: UserDefaults = .standard
    ) throws {
        let data = try JSONEncoder().encode(repositories)
        defaults.set(data, forKey: defaultsKey)
    }

    static func catalogURL(from input: String) throws -> URL {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !value.isEmpty,
            var components = URLComponents(string: value),
            let scheme = components.scheme?.lowercased(),
            components.host != nil
        else {
            throw RepositoryError.invalidURL
        }
        guard scheme == "https" || scheme == "http" else {
            throw RepositoryError.unsupportedScheme
        }
        components.fragment = nil
        guard var url = components.url else {
            throw RepositoryError.invalidURL
        }
        if url.pathExtension.lowercased() != "json" {
            url.appendPathComponent("index.json", isDirectory: false)
        }
        return url
    }

    static func fetchCatalog(
        from catalogURL: URL,
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
        let catalog = try JSONDecoder().decode(Catalog.self, from: data)
        let baseURL = catalogURL.deletingLastPathComponent()
        return Catalog(
            name: catalog.name,
            extensionList: .init(
                extensions: catalog.extensionList.extensions.map { entry in
                    .init(
                        name: entry.name,
                        packageName: entry.packageName,
                        resources: .init(
                            apkUrl: absolute(
                                entry.resources.apkUrl,
                                relativeTo: baseURL
                            ),
                            iconUrl: entry.resources.iconUrl.map {
                                absolute($0, relativeTo: baseURL)
                            },
                            jarUrl: absolute(
                                entry.resources.jarUrl,
                                relativeTo: baseURL
                            )
                        ),
                        extensionLib: entry.extensionLib,
                        versionCode: entry.versionCode,
                        versionName: entry.versionName,
                        contentWarning: entry.contentWarning,
                        sources: entry.sources.map { source in
                            .init(
                                id: source.id,
                                name: source.name,
                                language: source.language,
                                homeUrl: source.homeUrl.map {
                                    absolute($0, relativeTo: baseURL)
                                }
                            )
                        }
                    )
                }
            )
        )
    }

    private static func absolute(_ url: URL, relativeTo baseURL: URL) -> URL {
        guard url.scheme == nil else { return url }
        return URL(
            string: url.relativeString,
            relativeTo: baseURL
        )?.absoluteURL ?? url
    }
}
