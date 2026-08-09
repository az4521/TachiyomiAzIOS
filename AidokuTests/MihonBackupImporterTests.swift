@testable import Aidoku
import Foundation
import Testing

struct MihonBackupImporterTests {
    @Test func decodesStandardTachibkWithoutJavaHost() throws {
        var chapter = BackupTestProtobufWriter()
        chapter.string(1, "/chapter-1")
        chapter.string(2, "Chapter 1")
        chapter.int64(4, 1)
        chapter.float(9, 12.5)

        var tracking = BackupTestProtobufWriter()
        tracking.int64(1, 2)
        tracking.int64(3, 12_345)
        tracking.string(5, "Fixture Tracker")

        var manga = BackupTestProtobufWriter()
        manga.int64(1, 42)
        manga.string(2, "/fixture")
        manga.string(3, "Fixture Manga")
        manga.message(16, chapter.data)
        manga.int64(17, 7)
        manga.message(18, tracking.data)
        manga.int64(100, 1)

        var category = BackupTestProtobufWriter()
        category.string(1, "Reading")
        category.int64(3, 7)

        var source = BackupTestProtobufWriter()
        source.string(1, "Fixture Source")
        source.int64(2, 42)

        var root = BackupTestProtobufWriter()
        root.message(1, manga.data)
        root.message(2, category.data)
        root.message(101, source.data)

        let backup = try TachibkBackupCodec.decode(from: root.data)
        #expect(backup.manga?.first?.title == "Fixture Manga")
        #expect(backup.manga?.first?.sourceId == "mihon.42")
        #expect(backup.chapters?.first?.title == "Chapter 1")
        #expect(backup.chapters?.first?.chapter == 12.5)
        #expect(backup.library?.first?.categories == ["Reading"])
        #expect(backup.trackItems?.first?.id == "12345")
        #expect(backup.sources?.first?.id == "mihon.42")
    }

    @Test func tachibkRoundTripsNativeOnlyState() throws {
        let date = Date(timeIntervalSince1970: 1_722_000_000)
        let backup = Backup(
            library: [],
            history: [],
            manga: [],
            chapters: [],
            trackItems: [],
            readingSessions: [],
            updates: [],
            categories: [BackupCategory(title: "Reading", sort: 0)],
            sources: [],
            sourceLists: ["https://example.invalid/index.pb"],
            settings: ["Library.showAllCategory": .bool(true)],
            extensionRepositories: Data("repositories".utf8),
            date: date,
            name: "Round trip",
            automatic: true,
            version: "test"
        )

        let encoded = try TachibkBackupCodec.encode(backup)
        #expect(encoded.starts(with: [0x1f, 0x8b]))
        let decoded = try #require(
            TachibkBackupCodec.decodeNativeBackup(from: encoded)
        )
        #expect(decoded.name == backup.name)
        #expect(decoded.date == backup.date)
        #expect(decoded.categories == backup.categories)
        #expect(decoded.sourceLists == backup.sourceLists)
        #expect(decoded.settings == backup.settings)
        #expect(decoded.extensionRepositories == backup.extensionRepositories)
        #expect(decoded.automatic == true)
    }

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

    @Test func convertsZeroBasedMihonReadingProgress() {
        #expect(
            MihonBackupImporter.aidokuProgress(
                mihonLastPageRead: 0,
                hasHistory: false
            ) == 0
        )
        #expect(
            MihonBackupImporter.aidokuProgress(
                mihonLastPageRead: 0,
                hasHistory: true
            ) == 1
        )
        #expect(
            MihonBackupImporter.aidokuProgress(
                mihonLastPageRead: 12,
                hasHistory: true
            ) == 13
        )
        #expect(
            MihonBackupImporter.aidokuProgress(
                mihonLastPageRead: .max,
                hasHistory: true
            ) == .max
        )
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

    @Test func mergingMihonHistoryNeverRevertsReadState() {
        let existing = BackupHistory(
            dateRead: Date(timeIntervalSince1970: 20),
            sourceId: "mihon.1",
            chapterId: "/chapter-1",
            mangaId: "/title",
            progress: 15,
            total: 30,
            completed: true
        )
        let importedUnread = BackupHistory(
            dateRead: Date(timeIntervalSince1970: 10),
            sourceId: "mihon.1",
            chapterId: "/chapter-1",
            mangaId: "/title",
            progress: 3,
            total: 20,
            completed: false
        )
        let merged = BackupManager.mergeMihonHistory(
            existing: existing,
            imported: importedUnread
        )

        #expect(merged.completed)
        #expect(merged.progress == 15)
        #expect(merged.total == 30)
        #expect(merged.dateRead == existing.dateRead)
    }

    @Test func mergingMihonHistoryPromotesImportedReadState() {
        let existing = BackupHistory(
            dateRead: .distantPast,
            sourceId: "mihon.1",
            chapterId: "/chapter-1",
            mangaId: "/title",
            progress: 0,
            completed: false
        )
        let importedRead = BackupHistory(
            dateRead: Date(timeIntervalSince1970: 20),
            sourceId: "mihon.1",
            chapterId: "/chapter-1",
            mangaId: "/title",
            progress: 12,
            completed: true
        )
        let merged = BackupManager.mergeMihonHistory(
            existing: existing,
            imported: importedRead
        )

        #expect(merged.completed)
        #expect(merged.progress == 12)
        #expect(merged.dateRead == importedRead.dateRead)
    }
}

private struct BackupTestProtobufWriter {
    var data = Data()

    mutating func int64(_ field: Int, _ value: Int64) {
        varint(UInt64(field << 3))
        varint(UInt64(bitPattern: value))
    }

    mutating func string(_ field: Int, _ value: String) {
        message(field, Data(value.utf8))
    }

    mutating func message(_ field: Int, _ value: Data) {
        varint(UInt64((field << 3) | 2))
        varint(UInt64(value.count))
        data.append(value)
    }

    mutating func float(_ field: Int, _ value: Float) {
        varint(UInt64((field << 3) | 5))
        var bits = value.bitPattern.littleEndian
        Swift.withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }

    private mutating func varint(_ input: UInt64) {
        var value = input
        while value >= 0x80 {
            data.append(UInt8(value & 0x7f) | 0x80)
            value >>= 7
        }
        data.append(UInt8(value))
    }
}
