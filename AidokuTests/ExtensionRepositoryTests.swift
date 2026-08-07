@testable import Aidoku
import Foundation
import Testing

struct ExtensionRepositoryTests {
    @Test func startsWithoutConfiguredRepositories() throws {
        let suite = "ExtensionRepositoryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(
            TachiyomiXJarRepository.repositories(defaults: defaults).isEmpty
        )
    }

    @Test func normalizesRepositoryDirectoryAndIndexURLs() throws {
        #expect(
            try TachiyomiXJarRepository.catalogURL(
                from: "https://example.com/extensions"
            ).absoluteString ==
                "https://example.com/extensions/index.pb"
        )
        #expect(
            try TachiyomiXJarRepository.catalogURL(
                from: "https://example.com/custom.json?token=preserved#section"
            ).absoluteString ==
                "https://example.com/custom.json?token=preserved"
        )
        #expect(throws: (any Error).self) {
            try TachiyomiXJarRepository.catalogURL(
                from: "file:///tmp/index.json"
            )
        }
    }

    @Test func recognizesMihonAndTachiyomiAZStoreLinks() throws {
        let encoded =
            "https%3A%2F%2Fexample.com%2Fextensions%2Findex.pb"
        #expect(
            try TachiyomiXJarRepository.repositoryURL(
                fromDeepLink: URL(
                    string: "mihon://extension-store?url=\(encoded)"
                )!
            ) == "https://example.com/extensions/index.pb"
        )
        #expect(
            try TachiyomiXJarRepository.repositoryURL(
                fromDeepLink: URL(
                    string: "tachiyomiaz://extension-store?url=\(encoded)"
                )!
            ) == "https://example.com/extensions/index.pb"
        )
        #expect(
            try TachiyomiXJarRepository.repositoryURL(
                fromDeepLink: URL(
                    string: "tachiyomi://add-repo?url=\(encoded)"
                )!
            ) == "https://example.com/extensions/index.pb"
        )
        #expect(
            try TachiyomiXJarRepository.repositoryURL(
                fromDeepLink: URL(string: "tachiyomiaz://source")!
            ) == nil
        )
    }

    @Test func decodesCurrentProtobufStoreWithJarResources() async throws {
        let source = message([
            varintField(1, 42),
            stringField(2, "Example Source"),
            stringField(3, "en"),
            stringField(4, "https://example.com"),
        ])
        let resources = message([
            stringField(1, "apk/example.apk"),
            stringField(2, "icons/example.png"),
            stringField(501, "jar/example.jar"),
        ])
        let entry = message([
            stringField(1, "Example"),
            stringField(2, "org.example.extension"),
            bytesField(3, resources),
            stringField(4, "1.6"),
            varintField(5, 7),
            stringField(6, "1.6.7"),
            varintField(7, 1),
            bytesField(8, source),
        ])
        let list = bytesField(1, entry)
        let store = message([
            stringField(1, "Example Store"),
            bytesField(101, list),
        ])

        let catalog = try await TachiyomiXJarRepository.decodeCatalogData(
            store,
            catalogURL: URL(string: "https://example.com/index.pb")!
        )
        let extensionEntry = try #require(
            catalog.extensionList.extensions.first
        )
        #expect(catalog.name == "Example Store")
        #expect(extensionEntry.packageName == "org.example.extension")
        #expect(
            extensionEntry.resources.jarUrl.absoluteString ==
                "https://example.com/jar/example.jar"
        )
        #expect(extensionEntry.sources.first?.id == "42")
    }

    @Test func decodesEquivalentCurrentJSONStore() async throws {
        let json = """
        {
          "name": "JSON Store",
          "extensionList": {
            "extensions": [{
              "name": "Example",
              "packageName": "org.example.extension",
              "resources": {
                "apkUrl": "apk/example.apk",
                "iconUrl": "icons/example.png",
                "jarUrl": "jar/example.jar"
              },
              "extensionLib": "1.6",
              "versionCode": "7",
              "versionName": "1.6.7",
              "contentWarning": "CONTENT_WARNING_SAFE",
              "sources": [{
                "id": "42",
                "name": "Example Source",
                "language": "en",
                "homeUrl": "https://example.com"
              }]
            }]
          }
        }
        """
        let catalog = try await TachiyomiXJarRepository.decodeCatalogData(
            Data(json.utf8),
            catalogURL: URL(string: "https://example.com/index.json")!
        )
        #expect(catalog.name == "JSON Store")
        #expect(
            catalog.extensionList.extensions.first?.resources.jarUrl
                .absoluteString == "https://example.com/jar/example.jar"
        )
    }

    @Test func storesOnlyExplicitlyAddedRepositories() throws {
        let suite = "ExtensionRepositoryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let repository = TachiyomiXJarRepository.Repository(
            name: "User Repository",
            catalogURL: URL(string: "https://example.com/index.json")!
        )
        try TachiyomiXJarRepository.save(
            repositories: [repository],
            defaults: defaults
        )

        #expect(
            TachiyomiXJarRepository.repositories(defaults: defaults) ==
                [repository]
        )
    }

    @Test func restoresIconForPreviouslyInstalledExtension() throws {
        let oldManifest = """
        {
          "id": "eu.kanade.tachiyomi.extension.en.example",
          "name": "Example",
          "version": "1.0",
          "entryClass": "example.Extension",
          "sourceURL": "https://example.com/jar/tachiyomi-en.example-v1.0.jar",
          "sha256": "fixture"
        }
        """
        let manifest = try JSONDecoder().decode(
            JVMExtensionManifest.self,
            from: Data(oldManifest.utf8)
        )
        #expect(
            manifest.resolvedIconURL?.absoluteString ==
                "https://example.com/icon/tachiyomi-en.example.png"
        )
    }

    private func message(_ fields: [Data]) -> Data {
        fields.reduce(into: Data()) { $0.append($1) }
    }

    private func stringField(_ number: UInt64, _ value: String) -> Data {
        bytesField(number, Data(value.utf8))
    }

    private func bytesField(_ number: UInt64, _ value: Data) -> Data {
        var data = protobufVarint((number << 3) | 2)
        data.append(protobufVarint(UInt64(value.count)))
        data.append(value)
        return data
    }

    private func varintField(_ number: UInt64, _ value: UInt64) -> Data {
        var data = protobufVarint(number << 3)
        data.append(protobufVarint(value))
        return data
    }

    private func protobufVarint(_ value: UInt64) -> Data {
        var value = value
        var data = Data()
        repeat {
            var byte = UInt8(value & 0x7f)
            value >>= 7
            if value != 0 {
                byte |= 0x80
            }
            data.append(byte)
        } while value != 0
        return data
    }
}
