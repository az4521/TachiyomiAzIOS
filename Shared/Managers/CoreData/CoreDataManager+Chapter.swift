//
//  CoreDataManager+Chapter.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/13/22.
//

import CoreData
import AidokuRunner

extension CoreDataManager {

    static func normalizedScanlatorFilter(_ scanlators: [String]?) -> [String]? {
        scanlators?.isEmpty == false ? scanlators : nil
    }

    /// Remove all chapter objects.
    func clearChapters(context: NSManagedObjectContext? = nil) {
        clear(request: ChapterObject.fetchRequest(), context: context)
    }

    /// Gets all chapter objects.
    func getChapters(context: NSManagedObjectContext? = nil) -> [ChapterObject] {
        (try? (context ?? self.context).fetch(ChapterObject.fetchRequest())) ?? []
    }

    /// Gets all chapter objects for a source.
    func getChapters(sourceId: String, context: NSManagedObjectContext? = nil) -> [ChapterObject] {
        let context = context ?? self.context
        let request = ChapterObject.fetchRequest()
        request.predicate = NSPredicate(format: "sourceId == %@", sourceId)
        return (try? context.fetch(request)) ?? []
    }

    /// Get a particular chapter object.
    func getChapter(
        sourceId: String,
        mangaId: String,
        chapterId: String,
        context: NSManagedObjectContext? = nil
    ) -> ChapterObject? {
        let context = context ?? self.context
        let request = ChapterObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "id == %@ AND mangaId == %@ AND sourceId == %@ ",
            chapterId, mangaId, sourceId
        )
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Get the chapter objects for a manga.
    func getChapters(sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) -> [ChapterObject] {
        let context = context ?? self.context
        let request = ChapterObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "mangaId == %@ AND sourceId == %@",
            mangaId, sourceId
        )
        request.sortDescriptors = [NSSortDescriptor(key: "sourceOrder", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    func getChapters(sourceId: String, mangaId: String) async -> [Chapter] {
        await container.performBackgroundTask { context in
            let objects = self.getChapters(sourceId: sourceId, mangaId: mangaId, context: context)
            return objects.map { $0.toChapter() }
        }
    }

    /// Create a chapter object.
    @discardableResult
    func createChapter(
        _ chapter: AidokuRunner.Chapter,
        sourceId: String,
        mangaId: String,
        sourceOrder: Int,
        mangaObject: MangaObject? = nil,
        historyObject: HistoryObject? = nil,
        lookupHistory: Bool = true,
        context: NSManagedObjectContext? = nil
    ) -> ChapterObject? {
        let context = context ?? self.context
        guard let mangaObject = mangaObject ?? getManga(
            sourceId: sourceId,
            mangaId: mangaId,
            context: context
        ) else {
            return nil
        }
        let object = ChapterObject(context: context)
        object.load(
            from: chapter,
            sourceId: sourceId,
            mangaId: mangaId,
            sourceOrder: sourceOrder
        )
        object.manga = mangaObject
        object.history = historyObject
        if lookupHistory, historyObject == nil {
            object.history = getHistory(
                sourceId: sourceId,
                mangaId: mangaId,
                chapterId: chapter.id,
                context: context
            )
        }
        return object
    }

    /// Check if a chapter exists in the data store.
    func hasChapter(sourceId: String, mangaId: String, chapterId: String, context: NSManagedObjectContext? = nil) -> Bool {
        let context = context ?? self.context
        let request = ChapterObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "id == %@ AND mangaId == %@ AND sourceId == %@ ",
            chapterId, mangaId, sourceId
        )
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }

    /// Removes chapters for manga.
    func removeChapters(sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) {
        let context = context ?? self.context
        let chapters = getChapters(sourceId: sourceId, mangaId: mangaId, context: context)
        for chapter in chapters where chapter.fileInfo == nil {
            context.delete(chapter)
        }
    }

    /// Set a list of chapters for a manga.
    /// - Returns: New created chapters
    @discardableResult
    func setChapters(
        _ chapters: [AidokuRunner.Chapter],
        sourceId: String,
        mangaId: String,
        context: NSManagedObjectContext? = nil
    ) -> [ChapterObject] {
        let context = context ?? self.context
        guard let manga = self.getManga(sourceId: sourceId, mangaId: mangaId, context: context) else { return [] }

        // Index incoming chapters once. Extensions with thousands of chapters
        // otherwise turn the existing first(where:)/removeAll loop into O(n²).
        var incomingById: [String: (offset: Int, chapter: AidokuRunner.Chapter)] = [:]
        var incomingOrder: [String] = []
        incomingById.reserveCapacity(chapters.count)
        incomingOrder.reserveCapacity(chapters.count)
        for (offset, chapter) in chapters.enumerated() where incomingById[chapter.id] == nil {
            incomingById[chapter.id] = (offset, chapter)
            incomingOrder.append(chapter.id)
        }

        // update existing chapter objects
        let chapterObjects = getChapters(sourceId: sourceId, mangaId: mangaId, context: context)
        var handledChapterIds = Set<String>()
        handledChapterIds.reserveCapacity(chapterObjects.count)
        for object in chapterObjects {
            guard
                let incoming = incomingById[object.id],
                handledChapterIds.insert(object.id).inserted
            else {
                context.delete(object)
                continue
            }

            if object.locked && !incoming.chapter.locked {
                // Treat newly unlocked chapters as new so update tracking sees them.
                context.delete(object)
            } else {
                object.load(
                    from: incoming.chapter,
                    sourceId: sourceId,
                    mangaId: mangaId,
                    sourceOrder: incoming.offset
                )
                object.manga = manga
                incomingById[incoming.chapter.id] = nil
            }
        }

        // Fetch all history relationships once instead of once per new chapter.
        let historyByChapter = Dictionary(
            getHistoryForManga(sourceId: sourceId, mangaId: mangaId, context: context)
                .map { ($0.chapterId, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Create remaining chapters without issuing per-chapter existence queries.
        var newChaptersCreated = [ChapterObject]()
        newChaptersCreated.reserveCapacity(incomingById.count)
        for chapterId in incomingOrder {
            guard let incoming = incomingById[chapterId] else { continue }
            if let chapterObject = createChapter(
                incoming.chapter,
                sourceId: sourceId,
                mangaId: mangaId,
                sourceOrder: incoming.offset,
                mangaObject: manga,
                historyObject: historyByChapter[chapterId],
                lookupHistory: false,
                context: context
            ) {
                newChaptersCreated.append(chapterObject)
            }
        }
        return newChaptersCreated
    }

    /// Get the number of unread chapters for a manga.
    func unreadCount(
        sourceId: String,
        mangaId: String,
        lang: String?,
        scanlators: [String]?,
        context: NSManagedObjectContext? = nil
    ) -> Int {
        let scanlators = Self.normalizedScanlatorFilter(scanlators)
        let context = context ?? self.context
        let request = ChapterObject.fetchRequest()
        if let scanlators, let lang {
            request.predicate = NSPredicate(
                format: """
                sourceId == %@
                AND mangaId == %@
                AND lang == %@
                AND ((scanlator IN %@) OR (scanlator == nil AND %@ CONTAINS ''))
                AND (history == nil OR history.completed == false)
                AND locked == false
                """,
                sourceId, mangaId, lang, scanlators, scanlators
            )
        } else if let scanlators {
            request.predicate = NSPredicate(
                format: """
                sourceId == %@
                AND mangaId == %@
                AND ((scanlator IN %@) OR (scanlator == nil AND %@ CONTAINS ''))
                AND (history == nil OR history.completed == false)
                AND locked == false
                """,
                sourceId, mangaId, scanlators, scanlators
            )
        } else if let lang {
            request.predicate = NSPredicate(
                format: """
                sourceId == %@
                AND mangaId == %@
                AND lang == %@
                AND (history == nil OR history.completed == false)
                AND locked == false
                """,
                sourceId, mangaId, lang
            )
        } else {
            request.predicate = NSPredicate(
                format: """
                sourceId == %@
                AND mangaId == %@
                AND (history == nil OR history.completed == false)
                AND locked == false
                """,
                sourceId, mangaId
            )
        }
        return (try? context.count(for: request)) ?? 0
    }

    /// Count unread chapters for the complete library in one grouped store
    /// query. Titles with per-manga language or scanlator filters are uncommon
    /// and are corrected individually after the grouped query.
    func libraryUnreadCounts(
        context: NSManagedObjectContext
    ) -> [MangaIdentifier: Int] {
        let libraryRequest = LibraryMangaObject.fetchRequest()
        libraryRequest.predicate = NSPredicate(format: "manga != nil")
        libraryRequest.relationshipKeyPathsForPrefetching = ["manga"]
        guard let library = try? context.fetch(libraryRequest) else {
            return [:]
        }

        let mangaByIdentifier = Dictionary(
            library.compactMap { $0.manga }.map { ($0.identifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var counts = Dictionary(
            uniqueKeysWithValues: mangaByIdentifier.keys.map { ($0, 0) }
        )

        let count = NSExpressionDescription()
        count.name = "unreadCount"
        count.expression = NSExpression(
            forFunction: "count:",
            arguments: [NSExpression(forKeyPath: "id")]
        )
        count.expressionResultType = .integer64AttributeType

        let request = NSFetchRequest<NSDictionary>(entityName: "Chapter")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["sourceId", "mangaId", count]
        request.propertiesToGroupBy = ["sourceId", "mangaId"]
        request.predicate = NSPredicate(
            format: "locked == false AND (history == nil OR history.completed == false)"
        )
        if let rows = try? context.fetch(request) {
            for row in rows {
                guard
                    let sourceId = row["sourceId"] as? String,
                    let mangaId = row["mangaId"] as? String,
                    let value = row["unreadCount"] as? NSNumber
                else {
                    continue
                }
                let identifier = MangaIdentifier(
                    sourceKey: sourceId,
                    mangaKey: mangaId
                )
                if mangaByIdentifier[identifier] != nil {
                    counts[identifier] = value.intValue
                }
            }
        }

        for (identifier, manga) in mangaByIdentifier where
            manga.langFilter != nil || !(manga.scanlatorFilter?.isEmpty ?? true)
        {
            counts[identifier] = unreadCount(
                sourceId: identifier.sourceKey,
                mangaId: identifier.mangaKey,
                lang: manga.langFilter,
                scanlators: manga.scanlatorFilter,
                context: context
            )
        }
        return counts
    }

    /// Get the number of read chapters for a manga.
    func readCount(
        sourceId: String,
        mangaId: String,
        lang: String?,
        scanlators: [String]?,
        context: NSManagedObjectContext? = nil
    ) -> Int {
        let scanlators = Self.normalizedScanlatorFilter(scanlators)
        let context = context ?? self.context
        let request = ChapterObject.fetchRequest()
        if let scanlators, let lang {
            request.predicate = NSPredicate(
                format: """
                sourceId == %@
                AND mangaId == %@
                AND lang == %@
                AND ((scanlator IN %@) OR (scanlator == nil AND %@ CONTAINS ''))
                AND history.completed == true
                """,
                sourceId, mangaId, lang, scanlators, scanlators
            )
        } else if let scanlators {
            request.predicate = NSPredicate(
                format: """
                sourceId == %@
                AND mangaId == %@
                AND ((scanlator IN %@) OR (scanlator == nil AND %@ CONTAINS ''))
                AND history.completed == true
                """,
                sourceId, mangaId, scanlators, scanlators
            )
        } else if let lang {
            request.predicate = NSPredicate(
                format: "sourceId == %@ AND mangaId == %@ AND history != nil AND lang == %@ AND history.completed == true",
                sourceId, mangaId, lang
            )
        } else {
            request.predicate = NSPredicate(
                format: "sourceId == %@ AND mangaId == %@ AND history != nil AND history.completed == true",
                sourceId, mangaId
            )
        }
        return (try? context.count(for: request)) ?? 0
    }

    /// Get the number of chapters that have been started, including partially read chapters.
    func startedCount(
        sourceId: String,
        mangaId: String,
        lang: String?,
        scanlators: [String]?,
        context: NSManagedObjectContext? = nil
    ) -> Int {
        let scanlators = Self.normalizedScanlatorFilter(scanlators)
        let context = context ?? self.context
        let request = ChapterObject.fetchRequest()
        if let scanlators, let lang {
            request.predicate = NSPredicate(
                format: """
                sourceId == %@
                AND mangaId == %@
                AND lang == %@
                AND ((scanlator IN %@) OR (scanlator == nil AND %@ CONTAINS ''))
                AND history != nil
                """,
                sourceId, mangaId, lang, scanlators, scanlators
            )
        } else if let scanlators {
            request.predicate = NSPredicate(
                format: """
                sourceId == %@
                AND mangaId == %@
                AND ((scanlator IN %@) OR (scanlator == nil AND %@ CONTAINS ''))
                AND history != nil
                """,
                sourceId, mangaId, scanlators, scanlators
            )
        } else if let lang {
            request.predicate = NSPredicate(
                format: "sourceId == %@ AND mangaId == %@ AND lang == %@ AND history != nil",
                sourceId, mangaId, lang
            )
        } else {
            request.predicate = NSPredicate(
                format: "sourceId == %@ AND mangaId == %@ AND history != nil",
                sourceId, mangaId
            )
        }
        return (try? context.count(for: request)) ?? 0
    }
}
