import Foundation
import TachiJVMRunner

struct JVMExtensionManifest: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let version: String
    let entryClass: String
    let sourceURL: URL?
    let sha256: String

    init(
        inspection: JVMExtensionInspection,
        sourceURL: URL?,
        sha256: String
    ) {
        id = inspection.packageName
        name = inspection.name
        version = inspection.version
        entryClass = inspection.entryClass
        self.sourceURL = sourceURL
        self.sha256 = sha256
    }

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

struct JVMExtensionInspection: Hashable, Sendable {
    let packageName: String
    let name: String
    let version: String
    let versionCode: String
    let entryClass: String
    let extensionLibrary: String?
    let maximumClassVersion: Int
    let requiredJavaVersion: Int
    let runtimeCompatible: Bool

    init(response: ExtensionHostResponse) throws {
        guard
            response.success,
            let packageName = response.packageName,
            let name = response.name,
            let version = response.version,
            let versionCode = response.versionCode,
            let entryClass = response.entryClass,
            let maximumClassVersionText = response.maximumClassVersion,
            let maximumClassVersion = Int(maximumClassVersionText),
            let requiredJavaVersionText = response.requiredJavaVersion,
            let requiredJavaVersion = Int(requiredJavaVersionText)
        else {
            throw JVMSourceRuntime.RuntimeError.hostRejected(
                response.error ?? "The JAR metadata is incomplete."
            )
        }

        self.packageName = packageName
        self.name = name
        self.version = version
        self.versionCode = versionCode
        self.entryClass = entryClass
        self.extensionLibrary = response.extensionLibrary
        self.maximumClassVersion = maximumClassVersion
        self.requiredJavaVersion = requiredJavaVersion
        runtimeCompatible = response.runtimeCompatible == "true"
    }
}
