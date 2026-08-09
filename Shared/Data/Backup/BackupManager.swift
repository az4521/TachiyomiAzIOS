//
//  BackupManager.swift
//  Aidoku
//
//  Created by Skitty on 2/26/22.
//

import BackgroundTasks
import Foundation

#if canImport(UIKit)
import UIKit
#endif

private struct MihonMangaMergeKey: Hashable {
    let sourceId: String
    let url: String
}

actor BackupManager {
    static let shared = BackupManager()

    static let directory = FileManager.default.documentDirectory.appendingPathComponent("Backups", isDirectory: true)

    static var backupUrls: [URL] {
        Self.directory.contentsByDateModified.filter {
            $0.pathExtension.lowercased() == "tachibk"
        }
    }

    private static let backupTaskIdentifier = (Bundle.main.bundleIdentifier ?? "") + ".backup"
    private static let maxAutoBackups = 4

    private static let excludedSettings = [
        "Browse.sourceLists", // stored separately
        "General.icloudSync"
    ]
    static let excludedSettingsPrefixes = [
        "Flag",
        "Data"
    ]
    static let allowedSettingsPrefixes = [
        "General",
        "Library",
        "Browse",
        "History",
        "Reader",
        "Tracker",
        "Tracking",
        "AutomaticBackups",
        "Downloads",
        "Manga",
        "Logs",
        "Search",
        "Token"
    ]

    @discardableResult
    func save(backup: Backup, url: URL? = nil) async -> Bool {
        Self.directory.createDirectory()
        #if os(iOS)
        do {
            let encoded = try TachibkBackupCodec.encode(backup)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            if let url = url {
                try encoded.write(to: url, options: .atomic)
            } else {
                let path = Self.directory.appendingPathComponent(
                    "tachiyomiaz_\(dateFormatter.string(from: backup.date)).tachibk"
                )
                try encoded.write(to: path, options: .atomic)
            }
            NotificationCenter.default.post(name: Notification.Name("updateBackupList"), object: nil)
            return true
        } catch {
            LogManager.logger.error("Unable to save .tachibk backup: \(error)")
            return false
        }
        #else
        return false
        #endif
    }

    @discardableResult
    func saveNewBackup(name: String = "", options: BackupOptions) async -> Bool {
        await save(backup: await createBackup(name: name, options: options))
    }

    func importBackup(from url: URL) async -> Bool {
        #if os(iOS)
        guard url.pathExtension.lowercased() == "tachibk" else {
            return false
        }

        do {
            _ = try await MihonBackupImporter.load(from: url)
        } catch {
            LogManager.logger.error("Unable to import .tachibk backup: \(error)")
            return false
        }

        Self.directory.createDirectory()
        var targetLocation = Self.directory.appendingPathComponent(url.lastPathComponent)
        while targetLocation.exists {
            targetLocation = targetLocation.deletingLastPathComponent().appendingPathComponent(
                targetLocation.deletingPathExtension().lastPathComponent.appending("_1")
            ).appendingPathExtension(url.pathExtension)
        }
        let secured = url.startAccessingSecurityScopedResource()
        defer {
            if secured {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            try FileManager.default.copyItem(at: url, to: targetLocation)
            NotificationCenter.default.post(name: Notification.Name("updateBackupList"), object: nil)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    struct BackupOptions {
        var automatic: Bool = false
        let libraryEntries: Bool
        let history: Bool
        let chapters: Bool
        let tracking: Bool
        let readingSessions: Bool
        let updates: Bool
        let categories: Bool
        let settings: Bool
        let sourceLists: Bool
        let sensitiveSettings: Bool
    }

    func createBackup(name: String = "", options: BackupOptions) async -> Backup {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            let library: [BackupLibraryManga] = if options.libraryEntries {
                CoreDataManager.shared.getLibraryManga(context: context).map {
                    BackupLibraryManga(libraryObject: $0, skipCategories: !options.categories)
                }
            } else {
                []
            }
            let history: [BackupHistory] = if options.history {
                CoreDataManager.shared.getHistory(context: context).map {
                    BackupHistory(historyObject: $0)
                }
            } else {
                []
            }
            let manga: [BackupManga] = if options.libraryEntries {
                CoreDataManager.shared.getManga(context: context).map {
                    BackupManga(mangaObject: $0)
                }
            } else {
                []
            }
            let chapters: [BackupChapter] = if options.chapters {
                CoreDataManager.shared.getChapters(context: context).map {
                    BackupChapter(chapterObject: $0)
                }
            } else {
                []
            }
            let trackItems: [BackupTrackItem] = if options.tracking {
                CoreDataManager.shared.getTracks(context: context).compactMap {
                    BackupTrackItem(trackObject: $0)
                }
            } else {
                []
            }
            let sessionItems: [BackupReadingSession] = if options.readingSessions {
                CoreDataManager.shared.getSessions(context: context).compactMap(BackupReadingSession.init)
            } else {
                []
            }
            let updateItems: [BackupUpdate] = if options.updates {
                CoreDataManager.shared.getUpdates(context: context).compactMap(BackupUpdate.init)
            } else {
                []
            }
            let categories: [BackupCategory] = if options.categories {
                CoreDataManager.shared.getCategories(context: context).compactMap(BackupCategory.init)
            } else {
                []
            }
            let sources: [BackupSource] = CoreDataManager.shared.getSources(context: context).compactMap(BackupSource.init)
            let sourceLists = options.sourceLists ? SourceManager.shared.sourceListsStrings : []

            let settings: [String: JsonAnyValue]? = if options.settings {
                self.exportSettings(includeSensitive: options.sensitiveSettings, sourceKeys: sources.map(\.id))
            } else {
                nil
            }

            return Backup(
                library: library,
                history: history,
                manga: manga,
                chapters: chapters,
                trackItems: trackItems,
                readingSessions: sessionItems,
                updates: updateItems,
                categories: categories,
                sources: sources,
                sourceLists: sourceLists,
                settings: settings,
                extensionRepositories: options.settings
                    ? UserDefaults.standard.data(
                        forKey: "extensionRepositories"
                    )
                    : nil,
                date: Date.now,
                name: name.isEmpty ? nil : name,
                automatic: options.automatic,
                version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            )
        }
    }

    private nonisolated func exportSettings(includeSensitive: Bool, sourceKeys: [String]) -> [String: JsonAnyValue] {
        var allSettings = UserDefaults.standard.dictionaryRepresentation()

        // filter out potentially sensitive info
        if !includeSensitive {
            let sensitiveKeywords = ["login", "password", "token", "auth", "cookie"]
            for key in allSettings.keys where sensitiveKeywords.contains(where: key.lowercased().contains) {
                allSettings.removeValue(forKey: key)
            }
        }

        var convertedSettings: [String: JsonAnyValue] = [:]

        // convert to export compatible types
        for (key, value) in allSettings {
            guard
                Self.allowedSettingsPrefixes.contains(where: { key.hasPrefix($0) }) || sourceKeys.contains(where: { key.hasPrefix($0) }),
                !Self.excludedSettings.contains(key)
            else {
                continue
            }
            if let value = value as? String {
                convertedSettings[key] = .string(value)
            } else if let value = value as? Int {
                convertedSettings[key] = .int(value)
            } else if let value = value as? Double {
                convertedSettings[key] = .double(value)
            } else if let value = value as? Bool {
                convertedSettings[key] = .bool(value)
            } else if let value = value as? [String] {
                convertedSettings[key] = .array(value)
            }
        }

        return convertedSettings
    }

    func loadBackup(from url: URL) async -> Backup? {
        #if os(iOS)
        return try? await MihonBackupImporter.load(from: url)
        #else
        return nil
        #endif
    }

    func renameBackup(url: URL, name: String?) async {
        guard var backup = await loadBackup(from: url) else { return }
        backup.name = name?.isEmpty ?? true ? nil : name
        await save(backup: backup, url: url)
    }

    func removeBackup(url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: Restoring
extension BackupManager {
    enum BackupError: Error {
        case manga
        case categories
        case library
        case history
        case chapters
        case sessions
        case updates
        case track
        case sources

        var stringValue: String {
            switch self {
                case .manga: NSLocalizedString("CONTENT")
                case .categories: NSLocalizedString("CATEGORIES")
                case .library: NSLocalizedString("LIBRARY")
                case .history: NSLocalizedString("HISTORY")
                case .chapters: NSLocalizedString("CHAPTERS")
                case .sessions: NSLocalizedString("READING_SESSIONS")
                case .updates: NSLocalizedString("UPDATES")
                case .track: NSLocalizedString("TRACKERS")
                case .sources: NSLocalizedString("SOURCES")
            }
        }
    }

    @discardableResult
    func restore(from backup: Backup) async -> Bool {
        if backup.version == "Mihon/TachiyomiAZ" {
            return await mergeMihonBackup(backup)
        } else {
            return await doRestore(from: backup)
        }
    }

    private func cacheRestoredUnreadBadges() async {
        let counts = await CoreDataManager.shared.container
            .performBackgroundTask { context in
                CoreDataManager.shared.libraryUnreadCounts(context: context)
            }
        LibraryBadgeCache.save(counts, kind: .unread)
    }

    @discardableResult
    // swiftlint:disable:next function_body_length
    private func mergeMihonBackup(_ backup: Backup) async -> Bool {
#if !os(macOS)
        await MainActor.run {
            (UIApplication.shared.delegate as? AppDelegate)?
                .showLoadingIndicator()
            UIApplication.shared.isIdleTimerDisabled = true
        }
#endif

        let errorMessage = await CoreDataManager.shared.container
            .performBackgroundTask { context -> String? in
                let manager = CoreDataManager.shared

                do {
                    var categoriesByTitle = Dictionary(
                        manager.getCategories(context: context).compactMap {
                            category in category.title.map {
                                ($0, category)
                            }
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                    for item in backup.categories ?? [] {
                        guard
                            let title = item.title,
                            categoriesByTitle[title] == nil
                        else {
                            continue
                        }
                        categoriesByTitle[title] = manager.createCategory(
                            title: title,
                            context: context
                        )
                    }

                    var mangaByURL = Dictionary(
                        manager.getManga(context: context).map {
                            (MihonMangaMergeKey(
                                sourceId: $0.sourceId,
                                url: $0.url ?? $0.id
                            ), $0)
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                    var mangaByIdentifier = Dictionary(
                        manager.getManga(context: context).map {
                            ($0.identifier, $0)
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                    var targetIdentifiers: [
                        MangaIdentifier: MangaIdentifier
                    ] = [:]

                    for item in backup.manga ?? [] {
                        let backupIdentifier = MangaIdentifier(
                            sourceKey: item.sourceId,
                            mangaKey: item.id
                        )
                        let urlKey = MihonMangaMergeKey(
                            sourceId: item.sourceId,
                            url: item.url ?? item.id
                        )
                        let manga: MangaObject
                        if let existing = mangaByURL[urlKey] {
                            manga = existing
                        } else {
                            manga = item.toObject(context: context)
                            mangaByURL[urlKey] = manga
                            mangaByIdentifier[manga.identifier] = manga
                        }
                        targetIdentifiers[backupIdentifier] = manga.identifier
                    }

                    var libraryByIdentifier = Dictionary(
                        manager.getLibraryManga(context: context).compactMap {
                            object in object.manga.map {
                                ($0.identifier, object)
                            }
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                    for item in backup.library ?? [] {
                        let target = targetIdentifiers[item.identifier] ??
                            item.identifier
                        guard let manga = mangaByIdentifier[target] else {
                            continue
                        }
                        let library: LibraryMangaObject
                        if let existing = libraryByIdentifier[target] {
                            library = existing
                            if
                                let importedLastRead = item.lastRead,
                                importedLastRead >
                                    (existing.lastRead ?? .distantPast)
                            {
                                existing.lastRead = importedLastRead
                            }
                        } else {
                            library = item.toObject(context: context)
                            library.manga = manga
                            libraryByIdentifier[target] = library
                        }
                        for title in item.categories ?? [] {
                            if let category = categoriesByTitle[title] {
                                library.addToCategories(category)
                            }
                        }
                    }

                    var historyByIdentifier = Dictionary(
                        manager.getHistory(context: context).map {
                            ($0.identifier, $0)
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                    for item in backup.history ?? [] {
                        let backupManga = MangaIdentifier(
                            sourceKey: item.sourceId,
                            mangaKey: item.mangaId
                        )
                        let targetManga = targetIdentifiers[backupManga] ??
                            backupManga
                        var imported = item
                        imported.mangaId = targetManga.mangaKey
                        let target = ChapterIdentifier(
                            sourceKey: imported.sourceId,
                            mangaKey: imported.mangaId,
                            chapterKey: imported.chapterId
                        )
                        if let existing = historyByIdentifier[target] {
                            let merged = Self.mergeMihonHistory(
                                existing: BackupHistory(
                                    historyObject: existing
                                ),
                                imported: imported
                            )
                            existing.dateRead = merged.dateRead
                            existing.progress = Int16(
                                clamping: merged.progress ?? -1
                            )
                            existing.total = Int16(
                                clamping: merged.total ?? 0
                            )
                            existing.completed = merged.completed
                        } else {
                            let history = imported.toObject(context: context)
                            historyByIdentifier[target] = history
                        }
                    }

                    var chaptersByIdentifier = Dictionary(
                        manager.getChapters(context: context).map {
                            ($0.identifier, $0)
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                    for item in backup.chapters ?? [] {
                        let backupManga = MangaIdentifier(
                            sourceKey: item.sourceId,
                            mangaKey: item.mangaId
                        )
                        let targetManga = targetIdentifiers[backupManga] ??
                            backupManga
                        var imported = item
                        imported.mangaId = targetManga.mangaKey
                        let target = ChapterIdentifier(
                            sourceKey: imported.sourceId,
                            mangaKey: imported.mangaId,
                            chapterKey: imported.id
                        )
                        let chapter: ChapterObject
                        if let existing = chaptersByIdentifier[target] {
                            chapter = existing
                            existing.bookmarked = existing.bookmarked ||
                                (imported.bookmarked ?? false)
                        } else {
                            chapter = imported.toObject(context: context)
                            chaptersByIdentifier[target] = chapter
                        }
                        chapter.manga = mangaByIdentifier[targetManga]
                        if let history = historyByIdentifier[target] {
                            chapter.history = history
                            history.chapter = chapter
                        }
                    }

                    for item in backup.trackItems ?? [] {
                        let backupManga = MangaIdentifier(
                            sourceKey: item.sourceId,
                            mangaKey: item.mangaId
                        )
                        let targetManga = targetIdentifiers[backupManga] ??
                            backupManga
                        guard !manager.hasTrack(
                            trackerId: item.trackerId,
                            sourceId: targetManga.sourceKey,
                            mangaId: targetManga.mangaKey,
                            context: context
                        ) else {
                            continue
                        }
                        var imported = item
                        imported.sourceId = targetManga.sourceKey
                        imported.mangaId = targetManga.mangaKey
                        _ = imported.toObject(context: context)
                    }

                    try context.save()
                    return nil
                } catch {
                    context.rollback()
                    return error.localizedDescription
                }
            }

        if errorMessage == nil {
            await cacheRestoredUnreadBadges()
        }

        NotificationCenter.default.post(name: .updateHistory, object: "backupRestore")
        NotificationCenter.default.post(name: .updateTrackers, object: nil)
        NotificationCenter.default.post(name: .updateCategories, object: nil)
        NotificationCenter.default.post(name: .updateLibrary, object: nil)

#if !os(macOS)
        await Task { @MainActor in
            let delegate = UIApplication.shared.delegate as? AppDelegate
            await delegate?.hideLoadingIndicator()
            UIApplication.shared.isIdleTimerDisabled = false
            if let errorMessage {
                delegate?.presentAlert(
                    title: NSLocalizedString("BACKUP_ERROR"),
                    message: String(
                        format: NSLocalizedString("BACKUP_ERROR_TEXT"),
                        errorMessage
                    )
                )
            } else {
                let missingSources = (backup.sources ?? []).filter {
                    SourceManager.shared.source(for: $0.id) == nil &&
                        !CoreDataManager.shared.hasSource(id: $0.id)
                }
                var message = NSLocalizedString(
                    "BACKUP_RESTORE_COMPLETE_TEXT",
                    tableName: nil,
                    bundle: .main,
                    value: "The backup was restored successfully.",
                    comment: "Shown after a backup restore finishes"
                )
                if !missingSources.isEmpty {
                    message += "\n\n" + NSLocalizedString(
                        "MISSING_SOURCES_TEXT"
                    ) + missingSources.map { "\n- \($0.id)" }.joined()
                }
                delegate?.presentAlert(
                    title: NSLocalizedString(
                        "BACKUP_RESTORE_COMPLETE",
                        tableName: nil,
                        bundle: .main,
                        value: "Backup Restored",
                        comment: "Backup restore success alert title"
                    ),
                    message: message
                )
            }
        }.value
#endif

        return errorMessage == nil
    }

    nonisolated static func mergeMihonHistory(
        existing: BackupHistory,
        imported: BackupHistory
    ) -> BackupHistory {
        BackupHistory(
            dateRead: max(existing.dateRead, imported.dateRead),
            sourceId: existing.sourceId,
            chapterId: existing.chapterId,
            mangaId: existing.mangaId,
            progress: max(existing.progress ?? -1, imported.progress ?? -1),
            total: max(existing.total ?? 0, imported.total ?? 0),
            completed: existing.completed || imported.completed
        )
    }

    @discardableResult
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func doRestore(from backup: Backup) async -> Bool {
#if !os(macOS)
        await MainActor.run {
            (UIApplication.shared.delegate as? AppDelegate)?.showLoadingIndicator()
            UIApplication.shared.isIdleTimerDisabled = true
        }
#endif

        Task {
            // restore settings
            if let settings = backup.settings {
                // only restore source settings for sources installed, or built-in sources that will be added from the backup restore
                var sourceKeyPrefixes = SourceManager.shared.sources.map { "\($0.key)." }
                for additionalSource in backup.sources ?? [] where additionalSource.config != nil {
                    sourceKeyPrefixes.append("\(additionalSource.id).")
                }
                for (key, value) in settings {
                    let hasAllowedPrefix = Self.allowedSettingsPrefixes.contains(where: { key.hasPrefix($0) })
                        || sourceKeyPrefixes.contains(where: { key.hasPrefix($0) })
                    guard
                        hasAllowedPrefix,
                        !Self.excludedSettings.contains(key),
                        !Self.excludedSettingsPrefixes.contains(where: { key.hasPrefix($0) })
                    else {
                        continue
                    }
                    UserDefaults.standard.set(value.toRaw(), forKey: key)
                }
            }
            #if os(iOS)
            if let repositories = backup.extensionRepositories {
                UserDefaults.standard.set(
                    repositories,
                    forKey: "extensionRepositories"
                )
            }
            #endif

            #if !os(iOS)
            // Restore delegated source lists only on upstream-compatible
            // non-iOS targets.
            guard let sourceLists = backup.sourceLists else { return }
            SourceManager.shared.clearSourceLists()
            for sourceList in sourceLists {
                guard let sourceListURL = URL(string: sourceList) else { continue }
                _ = await SourceManager.shared.addSourceList(url: sourceListURL)
            }
            #endif
        }

        let mangaTask = Task {
            if let backupManga = backup.manga {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearManga(context: context)
                    for item in backupManga {
                        _ = item.toObject(context: context)
                    }
                    do {
                        try context.save()
                        return true
                    } catch {
                        return false
                    }
                }
                if !result {
                    throw BackupError.manga
                }
            }
        }
        let categoriesTask = Task {
            if let backupCategories = backup.categories {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearCategories(context: context)
                    for category in backupCategories {
                        _ = category.toObject(context: context)
                    }
                    do {
                        try context.save()
                        return true
                    } catch {
                        return false
                    }
                }
                if !result {
                    throw BackupError.categories
                }
            }
        }
        let libraryTask = Task {
            try await mangaTask.value
            try await categoriesTask.value
            if let backupLibrary = backup.library {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearLibrary(context: context)
                    let mangaByKey = Dictionary(
                        CoreDataManager.shared.getManga(context: context).map {
                            ($0.identifier, $0)
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                    let categoryByTitle = Dictionary(
                        CoreDataManager.shared.getCategories(context: context).compactMap { category in
                            category.title.map { ($0, category) }
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                    for libraryBackupItem in backupLibrary {
                        let libraryObject = libraryBackupItem.toObject(context: context)
                        if let manga = mangaByKey[libraryBackupItem.identifier] {
                            libraryObject.manga = manga
                            if let categories = libraryBackupItem.categories, !categories.isEmpty {
                                libraryObject.categories = NSSet(array: categories.compactMap { categoryByTitle[$0] })
                            }
                        }
                    }
                    do {
                        try context.save()
                        return true
                    } catch {
                        return false
                    }
                }
                if !result {
                    throw BackupError.library
                }
            }
        }
        let historyTask = Task {
            if let backupHistory = backup.history {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearHistory(context: context)
                    for item in backupHistory {
                        _ = item.toObject(context: context)
                    }
                    do {
                        try context.save()
                        return true
                    } catch {
                        return false
                    }
                }
                if !result {
                    throw BackupError.history
                }
            }
        }
        let chaptersTask = Task {
            try await historyTask.value // need to link chapters with history
            try await libraryTask.value // need to make sure manga objects aren't being modified
            if let backupChapters = backup.chapters {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearChapters(context: context)
                    let mangaByKey = Dictionary(
                        CoreDataManager.shared.getManga(context: context).map {
                            ($0.identifier, $0)
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                    let historyByKey = Dictionary(
                        CoreDataManager.shared.getHistory(context: context).map {
                            ($0.identifier, $0)
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                    for backupChapter in backupChapters {
                        let chapter = backupChapter.toObject(context: context)
                        chapter.manga = mangaByKey[chapter.identifier.mangaIdentifier]
                        chapter.history = historyByKey[chapter.identifier]
                    }
                    do {
                        try context.save()
                        return true
                    } catch {
                        return false
                    }
                }
                if !result {
                    throw BackupError.chapters
                }
            }
        }
        let updatesTask = Task {
            try await chaptersTask.value // need to link updates with chapters
            if let backupUpdates = backup.updates {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearUpdates(context: context)
                    let chaptersByKey = Dictionary(
                        CoreDataManager.shared.getChapters(context: context).map {
                            ($0.identifier, $0)
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                    for backupUpdate in backupUpdates {
                        let update = backupUpdate.toObject(context: context)
                        update.chapter = chaptersByKey[update.identifier]
                    }
                    do {
                        try context.save()
                        return true
                    } catch {
                        return false
                    }
                }
                if !result {
                    throw BackupError.updates
                }
            }
        }
        let sessionsTask = Task {
            try await chaptersTask.value // need to link sessions with history, after being updated by chapters
            if let backupSessions = backup.readingSessions {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearSessions(context: context)
                    let historyByKey = Dictionary(
                        CoreDataManager.shared.getHistory(context: context).map {
                            ($0.identifier, $0)
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                    for backupSession in backupSessions {
                        // ensure data is valid
                        guard backupSession.endDate > backupSession.startDate && backupSession.pagesRead > 0 else {
                            continue
                        }
                        let session = backupSession.toObject(context: context)
                        session.history = historyByKey[backupSession.identifier]
                    }
                    do {
                        try context.save()
                        return true
                    } catch {
                        return false
                    }
                }
                if !result {
                    throw BackupError.sessions
                }
            }
        }
        let trackTask = Task {
            if let backupTrackItems = backup.trackItems {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearTracks(context: context)
                    for item in backupTrackItems {
                        _ = item.toObject(context: context)
                    }
                    do {
                        try context.save()
                        return true
                    } catch {
                        return false
                    }
                }
                if !result {
                    throw BackupError.track
                }
            }
        }
        let sourceTask = Task {
            if let sourceItems = backup.sources {
                let (result, needsRefresh) = await CoreDataManager.shared.container.performBackgroundTask { context in
                    var needsRefresh = false
                    for item in sourceItems {
                        guard item.config != nil else { continue }
                        CoreDataManager.shared.removeSource(id: item.id, context: context)
                        _ = item.toObject(context: context)
                        needsRefresh = true
                    }
                    do {
                        try context.save()
                        return (true, needsRefresh)
                    } catch {
                        return (false, false)
                    }
                }
                if !result {
                    throw BackupError.sources
                }
                if needsRefresh {
                    await SourceManager.shared.reloadSources()
                }
            }
        }

        var backupError: Error?

        // wait for db changes to finish
        do {
            try await updatesTask.value
            try await sessionsTask.value
            try await trackTask.value
            try await sourceTask.value
        } catch {
            backupError = error
        }

        if backupError == nil {
            await cacheRestoredUnreadBadges()
        }

        NotificationCenter.default.post(name: .updateHistory, object: "backupRestore")
        NotificationCenter.default.post(name: .updateTrackers, object: nil)
        NotificationCenter.default.post(name: .updateCategories, object: nil)
        NotificationCenter.default.post(name: .updateLibrary, object: nil)

#if !os(macOS)
        await Task { @MainActor [backupError] in
            let delegate = UIApplication.shared.delegate as? AppDelegate
            await delegate?.hideLoadingIndicator()

            UIApplication.shared.isIdleTimerDisabled = false

            if let backupError {
                // show error alert
                delegate?.presentAlert(
                    title: NSLocalizedString("BACKUP_ERROR"),
                    message: String(
                        format: NSLocalizedString("BACKUP_ERROR_TEXT"),
                        (backupError as? BackupError)?.stringValue ?? NSLocalizedString("UNKNOWN")
                    )
                )
            } else {
                let missingSources = (backup.sources ?? []).filter {
                    SourceManager.shared.source(for: $0.id) == nil &&
                        !CoreDataManager.shared.hasSource(id: $0.id)
                }
                var message = NSLocalizedString(
                    "BACKUP_RESTORE_COMPLETE_TEXT",
                    tableName: nil,
                    bundle: .main,
                    value: "The backup was restored successfully.",
                    comment: "Shown after a backup restore finishes"
                )
                if !missingSources.isEmpty {
                    message += "\n\n" + NSLocalizedString(
                        "MISSING_SOURCES_TEXT"
                    ) + missingSources.map { "\n- \($0.id)" }.joined()
                }
                delegate?.presentAlert(
                    title: NSLocalizedString(
                        "BACKUP_RESTORE_COMPLETE",
                        tableName: nil,
                        bundle: .main,
                        value: "Backup Restored",
                        comment: "Backup restore success alert title"
                    ),
                    message: message
                )
            }
        }.value
#endif

        return backupError == nil
    }
}

// MARK: Automatic Backups
extension BackupManager {
    nonisolated func register() {
#if !os(macOS) && !targetEnvironment(simulator)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backupTaskIdentifier, using: nil) { @Sendable [weak self] task in
            guard let self, let task = task as? BGProcessingTask else { return }

            Task { @Sendable in
                await self.createAutoBackup()

                task.setTaskCompleted(success: true)
            }
        }
#endif
    }

    func scheduleAutoBackup() {
        guard UserDefaults.standard.bool(forKey: "AutomaticBackups.enabled") else {
#if !os(macOS) && !targetEnvironment(simulator)
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backupTaskIdentifier)
#endif
            return
        }

        let lastUpdated = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "AutomaticBackups.lastBackup"))
        let interval: Double = switch UserDefaults.standard.string(forKey: "AutomaticBackups.interval") {
            case "6hours": 21600
            case "12hours": 43200
            case "daily": 86400
            case "2days": 172800
            case "weekly": 604800
            default: 0
        }
        let nextUpdateTime = lastUpdated + interval

        if nextUpdateTime < Date.now {
            // interval time has passed, create auto backup now
            Task {
                await createAutoBackup()
            }
        } else {
#if !os(macOS) && !targetEnvironment(simulator)
            // schedule task for the future
            let request = BGProcessingTaskRequest(identifier: Self.backupTaskIdentifier)
            request.earliestBeginDate = nextUpdateTime
            request.requiresExternalPower = false
            request.requiresNetworkConnectivity = false

            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                LogManager.logger.error("Could not schedule automatic backup: \(error)")
            }
#endif
        }
    }

    private func createAutoBackup() async {
        guard UserDefaults.standard.bool(forKey: "AutomaticBackups.enabled") else { return }

        let libraryEntries = UserDefaults.standard.bool(forKey: "AutomaticBackups.libraryEntries")
        let history = UserDefaults.standard.bool(forKey: "AutomaticBackups.history")
        let chapters = UserDefaults.standard.bool(forKey: "AutomaticBackups.chapters")
        let tracking = UserDefaults.standard.bool(forKey: "AutomaticBackups.tracking")
        let readingSessions = UserDefaults.standard.bool(forKey: "AutomaticBackups.readingSessions")
        let updates = UserDefaults.standard.bool(forKey: "AutomaticBackups.updates")
        let categories = UserDefaults.standard.bool(forKey: "AutomaticBackups.categories")
        let settings = UserDefaults.standard.bool(forKey: "AutomaticBackups.settings")
        let sourceLists = UserDefaults.standard.bool(forKey: "AutomaticBackups.sourceLists")
        let sensitiveSettings = UserDefaults.standard.bool(forKey: "AutomaticBackups.sensitiveSettings")

        guard await self.saveNewBackup(
            options: .init(
                automatic: true,
                libraryEntries: libraryEntries,
                history: history,
                chapters: chapters,
                tracking: tracking,
                readingSessions: readingSessions,
                updates: updates,
                categories: categories,
                settings: settings,
                sourceLists: sourceLists,
                sensitiveSettings: sensitiveSettings
            )
        ) else { return }

        // update last auto backup time
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "AutomaticBackups.lastBackup")

        await cleanUpAutoBackups()
        scheduleAutoBackup() // schedule the next one
    }

    // ensure we keep only the latest maxAutoBackups automatic backups
    private func cleanUpAutoBackups() async {
        var autoBackups: [(URL, Backup)] = []
        for backupUrl in Self.backupUrls {
            let backup = await loadBackup(from: backupUrl)
            if let backup, backup.automatic ?? false {
                autoBackups.append((backupUrl, backup))
            }
        }
        while autoBackups.count > Self.maxAutoBackups {
            let oldestBackup = autoBackups
                .min { $0.1.date < $1.1.date }
            if let oldestBackup {
                removeBackup(url: oldestBackup.0)
                autoBackups.removeAll { $0.0 == oldestBackup.0 }
            } else {
                break
            }
        }
    }
}
