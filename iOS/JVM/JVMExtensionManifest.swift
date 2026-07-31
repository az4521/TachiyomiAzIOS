import Foundation

struct JVMExtensionManifest: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let version: String
    let entryClass: String
    let sourceURL: URL?
    let sha256: String

    var directoryName: String {
        id
            .unicodeScalars
            .map { scalar in
                CharacterSet.alphanumerics.contains(scalar)
                    ? String(scalar)
                    : "_"
            }
            .joined()
    }
}
