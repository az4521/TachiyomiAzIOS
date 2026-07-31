@testable import Aidoku
import Foundation
import Testing

struct ExtensionRepositoryTests {
    @Test func startsWithoutConfiguredRepositories() throws {
        let suite = "ExtensionRepositoryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(
            KeiyoushiJarRepository.repositories(defaults: defaults).isEmpty
        )
    }

    @Test func normalizesRepositoryDirectoryAndIndexURLs() throws {
        #expect(
            try KeiyoushiJarRepository.catalogURL(
                from: "https://example.com/extensions"
            ).absoluteString ==
                "https://example.com/extensions/index.json"
        )
        #expect(
            try KeiyoushiJarRepository.catalogURL(
                from: "https://example.com/custom.json?token=preserved#section"
            ).absoluteString ==
                "https://example.com/custom.json?token=preserved"
        )
        #expect(throws: (any Error).self) {
            try KeiyoushiJarRepository.catalogURL(
                from: "file:///tmp/index.json"
            )
        }
    }

    @Test func storesOnlyExplicitlyAddedRepositories() throws {
        let suite = "ExtensionRepositoryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let repository = KeiyoushiJarRepository.Repository(
            name: "User Repository",
            catalogURL: URL(string: "https://example.com/index.json")!
        )
        try KeiyoushiJarRepository.save(
            repositories: [repository],
            defaults: defaults
        )

        #expect(
            KeiyoushiJarRepository.repositories(defaults: defaults) ==
                [repository]
        )
    }
}
