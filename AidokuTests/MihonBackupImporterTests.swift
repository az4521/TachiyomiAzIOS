@testable import Aidoku
import Testing

struct MihonBackupImporterTests {
    @Test func mapsMihonAndTachiyomiAZViewerModes() {
        #expect(MihonBackupImporter.aidokuViewer(mihonFlags: 1) == 1)
        #expect(MihonBackupImporter.aidokuViewer(mihonFlags: 2) == 2)
        #expect(MihonBackupImporter.aidokuViewer(mihonFlags: 3) == 3)
        #expect(MihonBackupImporter.aidokuViewer(mihonFlags: 4) == 4)
        #expect(MihonBackupImporter.aidokuViewer(mihonFlags: 5) == 4)
        #expect(MihonBackupImporter.aidokuViewer(mihonFlags: 6) == 1)
        #expect(MihonBackupImporter.aidokuViewer(mihonFlags: 7) == 2)
    }

    @Test func mapsMihonPublishingStates() {
        #expect(MihonBackupImporter.aidokuStatus(mihonStatus: 0) == 0)
        #expect(MihonBackupImporter.aidokuStatus(mihonStatus: 1) == 1)
        #expect(MihonBackupImporter.aidokuStatus(mihonStatus: 2) == 2)
        #expect(MihonBackupImporter.aidokuStatus(mihonStatus: 3) == 0)
        #expect(MihonBackupImporter.aidokuStatus(mihonStatus: 4) == 2)
        #expect(MihonBackupImporter.aidokuStatus(mihonStatus: 5) == 3)
        #expect(MihonBackupImporter.aidokuStatus(mihonStatus: 6) == 4)
    }

    @Test func importsMultipleTachiyomiAZCategoriesWithoutIds() throws {
        let manga = MihonBackupImporter.Manga(
            source: "2499283573021220255",
            url: "/title",
            title: "Title",
            artist: nil,
            author: nil,
            description: nil,
            genre: [],
            status: 1,
            thumbnailUrl: nil,
            dateAdded: 0,
            viewer: 2,
            chapters: [],
            tracking: [],
            categories: [0, 1],
            favorite: true,
            chapterFlags: 0,
            viewerFlags: nil,
            history: [],
            updateStrategy: 0,
            excludedScanlators: [],
            notes: "",
            initialized: false
        )
        let payload = MihonBackupImporter.Payload(
            manga: [manga],
            categories: [
                .init(name: "Reading", order: 0, id: 0, flags: 0),
                .init(name: "Archive", order: 1, id: 0, flags: 0)
            ],
            sources: []
        )

        let backup = MihonBackupImporter.convert(payload)
        let categories = try #require(backup.library?.first?.categories)
        #expect(Set(categories) == Set(["Reading", "Archive"]))
    }
}
