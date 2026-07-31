import Foundation

enum KeiyoushiJarRepository {
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
}
