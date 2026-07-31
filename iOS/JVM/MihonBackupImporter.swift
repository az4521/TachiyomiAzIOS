import Foundation

enum MihonBackupImporter {
    struct Payload: Decodable {
        let manga: [Manga]
        let categories: [Category]
        let sources: [Source]
    }

    struct Manga: Decodable {
        let source: String
        let url: String
        let title: String
        let artist: String?
        let author: String?
        let description: String?
        let genre: [String]
        let status: Int
        let thumbnailUrl: String?
        let dateAdded: Int64
        let viewer: Int
        let chapters: [Chapter]
        let categories: [Int64]
        let favorite: Bool
        let chapterFlags: Int
        let viewerFlags: Int?
        let history: [History]
        let updateStrategy: Int
        let excludedScanlators: [String]
        let notes: String
        let initialized: Bool
    }

    struct Chapter: Decodable {
        let url: String
        let name: String
        let scanlator: String?
        let read: Bool
        let bookmark: Bool
        let lastPageRead: Int64
        let dateFetch: Int64
        let dateUpload: Int64
        let chapterNumber: Float
        let sourceOrder: Int64
    }

    struct History: Decodable {
        let url: String
        let lastRead: Int64
        let readDuration: Int64
    }

    struct Category: Decodable {
        let name: String
        let order: Int64
        let id: Int64
        let flags: Int64
    }

    struct Source: Decodable {
        let name: String
        let id: String
    }

    static func load(from url: URL) async throws -> Backup {
        let data = try await JVMSourceRuntime.shared.decodeMihonBackup(at: url)
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return convert(payload)
    }

    private static func convert(_ payload: Payload) -> Backup {
        let categoryNamesById = Dictionary(
            uniqueKeysWithValues: payload.categories.map { ($0.id, $0.name) }
        )
        let categoryNamesByOrder = Dictionary(
            uniqueKeysWithValues: payload.categories.map { ($0.order, $0.name) }
        )

        var backupManga: [BackupManga] = []
        var library: [BackupLibraryManga] = []
        var chapters: [BackupChapter] = []
        var history: [BackupHistory] = []

        for manga in payload.manga {
            let sourceId = manga.source
            let mangaId = manga.url
            let dateAdded = date(milliseconds: manga.dateAdded)
            let categoryNames = manga.categories.compactMap {
                categoryNamesById[$0] ?? categoryNamesByOrder[$0]
            }
            let histories = Dictionary(
                manga.history.map { ($0.url, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            backupManga.append(
                BackupManga(
                    id: mangaId,
                    sourceId: sourceId,
                    title: manga.title,
                    author: manga.author,
                    artist: manga.artist,
                    desc: manga.description,
                    tags: manga.genre,
                    cover: manga.thumbnailUrl,
                    url: manga.url,
                    status: manga.status,
                    viewer: manga.viewerFlags ?? manga.viewer,
                    neverUpdate: manga.updateStrategy == 1,
                    chapterFlags: manga.chapterFlags,
                    scanlatorFilter: manga.excludedScanlators
                )
            )

            if manga.favorite {
                let lastRead = manga.history
                    .map(\.lastRead)
                    .max()
                    .map { date(milliseconds: $0) }
                library.append(
                    BackupLibraryManga(
                        lastRead: lastRead,
                        dateAdded: dateAdded,
                        categories: categoryNames,
                        mangaId: mangaId,
                        sourceId: sourceId
                    )
                )
            }

            for chapter in manga.chapters {
                chapters.append(
                    BackupChapter(
                        sourceId: sourceId,
                        mangaId: mangaId,
                        id: chapter.url,
                        title: chapter.name,
                        scanlator: chapter.scanlator,
                        url: chapter.url,
                        chapter: chapter.chapterNumber,
                        dateUploaded: optionalDate(
                            milliseconds: chapter.dateUpload
                        ),
                        sourceOrder: Int(clamping: chapter.sourceOrder)
                    )
                )

                let matchingHistory = histories[chapter.url]
                if
                    chapter.read ||
                    chapter.lastPageRead > 0 ||
                    matchingHistory != nil
                {
                    let lastRead = matchingHistory?.lastRead ?? max(
                        chapter.dateUpload,
                        chapter.dateFetch
                    )
                    history.append(
                        BackupHistory(
                            dateRead: date(milliseconds: lastRead),
                            sourceId: sourceId,
                            chapterId: chapter.url,
                            mangaId: mangaId,
                            progress: Int(clamping: chapter.lastPageRead),
                            completed: chapter.read
                        )
                    )
                }
            }
        }

        return Backup(
            library: library,
            history: history,
            manga: backupManga,
            chapters: chapters,
            trackItems: [],
            readingSessions: [],
            updates: [],
            categories: payload.categories
                .sorted { $0.order < $1.order }
                .map {
                    BackupCategory(
                        title: $0.name,
                        sort: Int(clamping: $0.order)
                    )
                },
            sources: payload.sources.map { BackupSource(id: $0.id) },
            sourceLists: [],
            settings: nil,
            date: .now,
            name: "Imported Mihon backup",
            automatic: false,
            version: "Mihon/TachiyomiAZ"
        )
    }

    private static func date(milliseconds: Int64) -> Date {
        guard milliseconds > 0 else { return .distantPast }
        return Date(
            timeIntervalSince1970: TimeInterval(milliseconds) / 1_000
        )
    }

    private static func optionalDate(milliseconds: Int64) -> Date? {
        guard milliseconds > 0 else { return nil }
        return date(milliseconds: milliseconds)
    }
}
