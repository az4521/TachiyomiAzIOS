//
//  MangaManager.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/14/22.
//

import AidokuRunner
import BackgroundTasks
import CoreData
import Nuke

#if canImport(UIKit)
import UIKit
#endif

struct LibraryMembershipSnapshot: Sendable {
    let identifier: MangaIdentifier
    let categories: [String]
    let lastOpened: Date
    let lastUpdated: Date
    let lastUpdatedChapters: Date
    let lastChapter: Date?
    let lastRead: Date?
    let dateAdded: Date
}

actor MangaManager {
    static let shared = MangaManager()

    private static let taskIdentifier = (Bundle.main.bundleIdentifier ?? "") + ".libraryRefresh"
    private static let continuedTaskIdentifier =
        (Bundle.main.bundleIdentifier ?? "") + ".libraryRefresh.continued.manual"

    private var libraryRefreshTask: Task<(), Never>?
    private var libraryRefreshProgressTask: Task<(), Never>?
    private var onLibraryRefreshProgress: (@MainActor (Progress) -> Void)?
    private var continuedTaskRegistered = false

    private var targetCategory: String?
    private var skipReachabilityCheck: Bool = false

#if !os(macOS)
    private var foregroundLibraryBackgroundTask: UIBackgroundTaskIdentifier = .invalid
#endif

    private static let maxConcurrentLibraryUpdateTasks = 10

    nonisolated func getNextChapter(
        manga: AidokuRunner.Manga,
        chapters: [AidokuRunner.Chapter],
        readingHistory: [String: (page: Int, date: Int)],
        sortAscending: Bool,
        downloadStatuses: [String: DownloadStatus]? = nil
    ) -> AidokuRunner.Chapter? {
        let resumeLastOpened = UserDefaults.standard.bool(forKey: "Library.resumeLastOpenedChapter")

        // 1. Resume Reading: Find the most recently read chapter that isn't
        // completed, unless the "resume last opened" option is enabled.
        var selectedChapter: AidokuRunner.Chapter?
        var selectedDate: Int = -1

        for chapter in chapters {
            guard
                let history = readingHistory[chapter.id],
                resumeLastOpened || history.page != -1,
                history.date > selectedDate
            else { continue }

            if chapter.locked {
                let isDownloaded = if let downloadStatuses {
                    downloadStatuses[chapter.key] == .finished
                } else {
                    DownloadManager.shared.getDownloadStatus(
                        for: .init(
                            sourceKey: manga.sourceKey,
                            mangaKey: manga.key,
                            chapterKey: chapter.key
                        )
                    ) == .finished
                }
                guard isDownloaded else { continue }
            }

            selectedDate = history.date
            selectedChapter = chapter
        }

        if let selectedChapter {
            return selectedChapter
        }

        // 2. Fallback: Find first uncompleted chapter in sort order (Start Reading)
        let sorted = sortAscending ? chapters : chapters.reversed()

        return sorted.first(where: { chapter in
            let isDownloaded = if let downloadStatuses {
                downloadStatuses[chapter.key] == .finished
            } else {
                DownloadManager.shared.getDownloadStatus(
                    for: .init(
                        sourceKey: manga.sourceKey,
                        mangaKey: manga.key,
                        chapterKey: chapter.key
                    )
                ) == .finished
            }
            let isUnlocked = !chapter.locked || isDownloaded
            let history = readingHistory[chapter.id]
            let isCompleted = history?.page ?? 0 == -1

            return isUnlocked && !isCompleted
        })
    }
}

// MARK: - Library Managing
extension MangaManager {
    func addToLibrary(
        manga: AidokuRunner.Manga,
        chapters: [AidokuRunner.Chapter] = [],
        fetchMangaDetails: Bool = false
    ) async {
        var manga = manga
        var chapters = chapters
        // update manga or chapters
        if fetchMangaDetails || chapters.isEmpty {
            if let source = SourceManager.shared.source(for: manga.sourceKey) {
                manga = (try? await source.getMangaUpdate(manga: manga, needsDetails: fetchMangaDetails, needsChapters: chapters.isEmpty)) ?? manga
                chapters = manga.chapters ?? chapters
            }
        }
        await CoreDataManager.shared.container.performBackgroundTask { [manga, chapters] context in
            CoreDataManager.shared.addToLibrary(
                manga: manga,
                chapters: chapters,
                context: context
            )
            // add to default category
            let defaultCategory = UserDefaults.standard.string(forKey: "Library.defaultCategory")
            if let defaultCategory {
                let hasCategory = CoreDataManager.shared.hasCategory(title: defaultCategory, context: context)
                if hasCategory {
                    CoreDataManager.shared.addCategoriesToManga(
                        sourceId: manga.sourceKey,
                        mangaId: manga.key,
                        categories: [defaultCategory],
                        context: context
                    )
                }
            }
            do {
                try context.save()
            } catch {
                LogManager.logger.error("MangaManager.addToLibrary: \(error.localizedDescription)")
            }
        }
        // add enhanced trackers
        await TrackerManager.shared.bindEnhancedTrackers(manga: manga)

        NotificationCenter.default.post(name: .addToLibrary, object: manga)
        NotificationCenter.default.post(name: .updateLibrary, object: nil)
    }

    func removeFromLibrary(sourceId: String, mangaId: String) async {
        _ = await removeFromLibrary(
            manga: [.init(sourceKey: sourceId, mangaKey: mangaId)]
        )
    }

    /// Remove only library membership for all identifiers in one transaction.
    /// Manga, chapters, history, downloads, and tracker bindings remain stored.
    @discardableResult
    func removeFromLibrary(
        manga identifiers: [MangaIdentifier]
    ) async -> [LibraryMembershipSnapshot] {
        let selected = Set(identifiers)
        guard !selected.isEmpty else { return [] }

        let sendsItemNotification = selected.count == 1
        let result = await CoreDataManager.shared.container.performBackgroundTask {
            @Sendable context -> ([LibraryMembershipSnapshot], AidokuRunner.Manga?) in
            var snapshots: [LibraryMembershipSnapshot] = []
            var removedManga: AidokuRunner.Manga?
            snapshots.reserveCapacity(selected.count)

            for libraryObject in CoreDataManager.shared.getLibraryManga(
                context: context
            ) {
                guard
                    let mangaObject = libraryObject.manga,
                    selected.contains(mangaObject.identifier)
                else {
                    continue
                }
                snapshots.append(
                    .init(
                        identifier: mangaObject.identifier,
                        categories: (libraryObject.categories?.allObjects as? [CategoryObject])?
                            .compactMap(\.title) ?? [],
                        lastOpened: libraryObject.lastOpened,
                        lastUpdated: libraryObject.lastUpdated,
                        lastUpdatedChapters: libraryObject.lastUpdatedChapters,
                        lastChapter: libraryObject.lastChapter,
                        lastRead: libraryObject.lastRead,
                        dateAdded: libraryObject.dateAdded
                    )
                )
                if sendsItemNotification {
                    removedManga = mangaObject.toNewManga()
                }
                context.delete(libraryObject)
            }

            do {
                try context.save()
                return (snapshots, removedManga)
            } catch {
                context.rollback()
                LogManager.logger.error(
                    "MangaManager.removeFromLibrary(batch): " +
                        error.localizedDescription
                )
                return ([], nil)
            }
        }

        // Item-level observers only need a notification for the single-title
        // path. A bulk operation uses one library refresh instead of hundreds
        // of collection-view reload notifications.
        if let manga = result.1 {
            NotificationCenter.default.post(
                name: .removeFromLibrary,
                object: manga
            )
        }
        NotificationCenter.default.post(name: .updateLibrary, object: nil)
        return result.0
    }

    /// Restore membership from the lightweight snapshot used by UndoManager.
    func restoreLibraryMembership(
        _ snapshots: [LibraryMembershipSnapshot]
    ) async {
        guard !snapshots.isEmpty else { return }
        let sendsItemNotification = snapshots.count == 1
        let restored = await CoreDataManager.shared.container.performBackgroundTask {
            @Sendable context -> AidokuRunner.Manga? in
            let categoriesByTitle = Dictionary(
                CoreDataManager.shared.getCategories(
                    sorted: false,
                    context: context
                ).compactMap { category in
                    category.title.map { ($0, category) }
                },
                uniquingKeysWith: { first, _ in first }
            )
            var restoredManga: AidokuRunner.Manga?

            for snapshot in snapshots {
                guard
                    let mangaObject = CoreDataManager.shared.getManga(
                        sourceId: snapshot.identifier.sourceKey,
                        mangaId: snapshot.identifier.mangaKey,
                        context: context
                    ),
                    mangaObject.libraryObject == nil
                else {
                    continue
                }
                let libraryObject = LibraryMangaObject(context: context)
                libraryObject.manga = mangaObject
                libraryObject.lastOpened = snapshot.lastOpened
                libraryObject.lastUpdated = snapshot.lastUpdated
                libraryObject.lastUpdatedChapters = snapshot.lastUpdatedChapters
                libraryObject.lastChapter = snapshot.lastChapter
                libraryObject.lastRead = snapshot.lastRead
                libraryObject.dateAdded = snapshot.dateAdded
                libraryObject.categories = NSSet(
                    array: snapshot.categories.compactMap {
                        categoriesByTitle[$0]
                    }
                )
                if sendsItemNotification {
                    restoredManga = mangaObject.toNewManga()
                }
            }

            do {
                try context.save()
                return restoredManga
            } catch {
                context.rollback()
                LogManager.logger.error(
                    "MangaManager.restoreLibraryMembership: " +
                        error.localizedDescription
                )
                return nil
            }
        }

        if let manga = restored {
            NotificationCenter.default.post(name: .addToLibrary, object: manga)
        }
        NotificationCenter.default.post(name: .updateLibrary, object: nil)
    }

    func restoreToLibrary(
        manga: Manga,
        chapters: [Chapter],
        trackItems: [TrackItem],
        categories: [String]
    ) async {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.addToLibrary(
                manga: manga.toNew(),
                chapters: chapters.map { $0.toNew() },
                context: context
            )

            if let libraryObject = CoreDataManager.shared.getLibraryManga(
                sourceId: manga.sourceId,
                mangaId: manga.id,
                context: context
            ) {
                if
                    let lastOpened = manga.lastOpened,
                    let lastUpdated = manga.lastUpdated,
                    let lastUpdatedChapters = manga.lastUpdatedChapters,
                    let dateAdded = manga.dateAdded
                {
                    libraryObject.lastOpened = lastOpened
                    libraryObject.lastUpdated = lastUpdated
                    libraryObject.lastUpdatedChapters = lastUpdatedChapters
                    libraryObject.lastChapter = manga.lastChapter
                    libraryObject.lastRead = manga.lastRead
                    libraryObject.dateAdded = dateAdded
                }
            }

            for item in trackItems {
                CoreDataManager.shared.createTrack(
                    id: item.id, trackerId: item.trackerId, sourceId: item.sourceId,
                    mangaId: item.mangaId, title: item.title, context: context)
            }

            for category in categories {
                let hasCategory = CoreDataManager.shared.hasCategory(
                    title: category, context: context)
                if !hasCategory {
                    CoreDataManager.shared.createCategory(title: category, context: context)
                }
            }
            CoreDataManager.shared.addCategoriesToManga(
                sourceId: manga.sourceId,
                mangaId: manga.id,
                categories: categories,
                context: context
            )

            do {
                try context.save()
            } catch {
                LogManager.logger.error(
                    "MangaManager.restoreToLibrary: \(error.localizedDescription)")
            }
        }
    }

    static func shouldAskForCategories() -> Bool {
        let categories = CoreDataManager.shared.getCategoryTitles()
        guard !categories.isEmpty else { return false }
        if
            let defaultCategory = UserDefaults.standard.string(forKey: "Library.defaultCategory"),
            defaultCategory == "none" || categories.contains(defaultCategory)
        {
            return false
        }
        return true
    }
}

// MARK: - Category Managing
extension MangaManager {
    func setCategories(sourceId: String, mangaId: String, categories: [String]) async {
        await CoreDataManager.shared.setMangaCategories(
            sourceId: sourceId,
            mangaId: mangaId,
            categories: categories
        )
        NotificationCenter.default.post(
            name: Notification.Name("updateMangaCategories"),
            object: MangaInfo(mangaId: mangaId, sourceId: sourceId)
        )
    }
}

// MARK: - Library Updating
extension MangaManager {
    nonisolated func register() {
#if !os(macOS) && !targetEnvironment(simulator)
        let processingRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { @Sendable [weak self] task in
            guard let self else { return }
            let completion = BackgroundTaskCompletionGate()

            task.expirationHandler = {
                completion.complete(task, success: false)
                Task {
                    await self.libraryRefreshTask?.cancel()
                }
            }

            Task { @Sendable in
                // BGTaskScheduler requests are one-shot. Queue the next request
                // before starting any network work so the schedule survives an
                // update failure or the app being suspended during the refresh.
                await self.scheduleNextLibraryRefresh(after: .now)
                await self.refreshLibrary(category: self.targetCategory, task: task as? ProgressReporting)

                completion.complete(task, success: true)
            }
        }
        if !processingRegistered {
            LogManager.logger.error(
                "Unable to register the deferred library refresh task"
            )
        }

        if #available(iOS 26.0, *) {
            let continuedRegistered = BGTaskScheduler.shared.register(
                forTaskWithIdentifier: Self.continuedTaskIdentifier,
                using: nil
            ) { @Sendable [weak self] task in
                guard let self else { return }
                let completion = BackgroundTaskCompletionGate()

                task.expirationHandler = {
                    completion.complete(task, success: false)
                    Task {
                        await self.libraryRefreshTask?.cancel()
                    }
                }

                Task { @Sendable in
                    await self.refreshLibrary(
                        category: self.targetCategory,
                        task: task as? ProgressReporting
                    )
                    await self.scheduleNextLibraryRefresh(after: .now)
                    completion.complete(task, success: true)
                }
            }
            Task {
                await self.setContinuedTaskRegistered(continuedRegistered)
            }
            if !continuedRegistered {
                LogManager.logger.error(
                    "Unable to register the continued library refresh task"
                )
            }
        }
#endif
    }

    private func setContinuedTaskRegistered(_ registered: Bool) {
        continuedTaskRegistered = registered
    }

    nonisolated static func libraryUpdateInterval(for value: String?) -> TimeInterval? {
        switch value {
            case "12hours": 43_200
            case "daily": 86_400
            case "2days": 172_800
            case "weekly": 604_800
            default: nil
        }
    }

    nonisolated static func nextLibraryRefreshDate(
        after date: Date,
        intervalValue: String?
    ) -> Date? {
        guard let interval = libraryUpdateInterval(for: intervalValue) else {
            return nil
        }
        return date.addingTimeInterval(interval)
    }

    func scheduleLibraryRefresh() async {
        let lastUpdated = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "Library.lastUpdated"))
        let intervalValue = UserDefaults.standard.string(forKey: "Library.updateInterval")
        guard let nextUpdateTime = Self.nextLibraryRefreshDate(
            after: lastUpdated,
            intervalValue: intervalValue
        ) else {
#if !os(macOS) && !targetEnvironment(simulator)
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
#endif
            return
        }

        if nextUpdateTime <= Date.now {
            // interval time has passed, refresh now
            await refreshLibrary()

            // A refresh can finish without changing Library.lastUpdated (for
            // example, when Wi-Fi-only updating is blocked). Rebase from now so
            // launch does not immediately retry the same overdue refresh.
            scheduleNextLibraryRefresh(after: .now)
        } else {
            submitLibraryRefresh(at: nextUpdateTime)
        }
    }

    func backgroundRefreshLibrary(category: String? = nil, skipReachabilityCheck: Bool = false) async {
        targetCategory = category
        self.skipReachabilityCheck = skipReachabilityCheck

#if !os(macOS) && !targetEnvironment(simulator)
        if #available(iOS 26.0, *),
           continuedTaskRegistered,
           UserDefaults.standard.bool(forKey: "Library.backgroundRefresh"),
           !ProcessInfo.processInfo.isMacCatalystApp
        {
            let request = BGContinuedProcessingTaskRequest(
                identifier: Self.continuedTaskIdentifier,
                title: NSLocalizedString("REFRESHING_LIBRARY"),
                subtitle: NSLocalizedString("PROCESSING_ENTRIES")
            )
            request.strategy = .fail
            do {
                try BGTaskScheduler.shared.submit(request)
                return
            } catch {
                LogManager.logger.error("Failed to start background library refresh: \(error)")
            }
        }
#endif

#if !os(macOS)
        if UserDefaults.standard.bool(forKey: "Library.backgroundRefresh") {
            // A processing request lets iOS resume the refresh later if the
            // foreground execution allowance expires. beginBackgroundTask
            // keeps the user-started refresh moving during the usual app
            // switch/lock-screen grace period on iOS 15 and later.
            submitLibraryRefresh(at: .now)
            await beginLibraryBackgroundExecution()
        }
#endif

        await refreshLibrary(category: category)
        scheduleNextLibraryRefresh(after: .now)

#if !os(macOS)
        await endLibraryBackgroundExecution()
#endif
    }

#if !os(macOS)
    private func beginLibraryBackgroundExecution() async {
        guard foregroundLibraryBackgroundTask == .invalid else { return }
        foregroundLibraryBackgroundTask = await MainActor.run {
            UIApplication.shared.beginBackgroundTask(
                withName: "TachiyomiAZ Library Update"
            ) { [weak self] in
                Task {
                    await self?.handleLibraryForegroundExpiration()
                }
            }
        }
    }

    private func endLibraryBackgroundExecution() async {
        guard foregroundLibraryBackgroundTask != .invalid else { return }
        let identifier = foregroundLibraryBackgroundTask
        foregroundLibraryBackgroundTask = .invalid
        await MainActor.run {
            UIApplication.shared.endBackgroundTask(identifier)
        }
    }

    private func handleLibraryForegroundExpiration() async {
        // Ending the short foreground allowance lets iOS suspend this work.
        // Keep the refresh task and its pending BGProcessing request intact so
        // the system can resume it instead of treating a screen lock/app switch
        // as a user cancellation.
        await endLibraryBackgroundExecution()
        await NotificationManager.shared.finishProgress(
            .libraryUpdate,
            success: false
        )
    }
#endif

    private func scheduleNextLibraryRefresh(after date: Date) {
        let intervalValue = UserDefaults.standard.string(forKey: "Library.updateInterval")
        guard let nextUpdateTime = Self.nextLibraryRefreshDate(
            after: date,
            intervalValue: intervalValue
        ) else {
#if !os(macOS) && !targetEnvironment(simulator)
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
#endif
            return
        }
        submitLibraryRefresh(at: nextUpdateTime)
    }

    private func submitLibraryRefresh(at date: Date) {
#if !os(macOS) && !targetEnvironment(simulator)
        // Rescheduling also handles interval changes while a request is pending.
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)

        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = date
        request.requiresExternalPower = false
        request.requiresNetworkConnectivity = true

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            LogManager.logger.error("Could not schedule library refresh: \(error)")
        }
#endif
    }

    /// Refresh manga objects in library.
    func refreshLibrary(
        category: String? = nil,
        forceAll: Bool = false,
        task: (ProgressReporting & Sendable)? = nil
    ) async {
#if !os(macOS)
        let tabController = await UIApplication.shared.firstKeyWindow?.rootViewController as? TabBarController
#endif

        if libraryRefreshTask != nil {
            // wait for already running library refresh
            await libraryRefreshTask?.value
        } else {
            // spawn new library refresh
            libraryRefreshTask = Task {
                await doLibraryRefresh(
                    category: category,
                    skipReachabilityCheck: skipReachabilityCheck,
                    forceAll: forceAll,
                    task: task,
                    refreshStarted: {
#if !os(macOS)
                        await tabController?.showLibraryRefreshView()

                        self.onLibraryRefreshProgress = { progress in
                            tabController?.setLibraryRefreshProgress(Float(progress.fractionCompleted))
                            task?.progress.totalUnitCount = progress.totalUnitCount
                            task?.progress.completedUnitCount = progress.completedUnitCount
                            if #available(iOS 26.0, *), let task = task as? BGContinuedProcessingTask {
                                task.updateTitle(
                                    NSLocalizedString("REFRESHING_LIBRARY"),
                                    subtitle: String(
                                        format: NSLocalizedString("%i_OF_%i"),
                                        Int(progress.completedUnitCount),
                                        Int(progress.totalUnitCount)
                                    )
                                )
                            }
                        }
#endif
                    }
                )
                libraryRefreshTask = nil
            }
            await libraryRefreshTask?.value
        }
        onLibraryRefreshProgress = nil

        self.targetCategory = nil
        self.skipReachabilityCheck = false

#if !os(macOS)
        // wait 0.5s for final progress animation to complete
        try? await Task.sleep(nanoseconds: 500_000_000)
        await tabController?.hideAccessoryView()
#endif

        NotificationCenter.default.post(name: .updateLibrary, object: nil)
    }

    /// Check if a manga should skip updating based on skip options.
    private func shouldSkip(
        manga: Manga,
        options: [String],
        excludedCategories: [String] = [],
        context: NSManagedObjectContext? = nil
    ) -> Bool {
        // update strategy is never
        if manga.updateStrategy == .never {
            return true
        }
        // next update time hasn't been reached
        if let nextUpdateTime = manga.nextUpdateTime {
            if nextUpdateTime > Date() {
                return true
            }
        }
        // completed
        if options.contains("completed") && manga.status == .completed {
            return true
        }
        // has unread chapters
        if options.contains("hasUnread") && CoreDataManager.shared.unreadCount(
            sourceId: manga.sourceId,
            mangaId: manga.id,
            lang: manga.langFilter,
            scanlators: manga.scanlatorFilter,
            context: context
        ) > 0 {
            return true
        }
        // has no read chapters
        if options.contains("notStarted") && CoreDataManager.shared.readCount(
            sourceId: manga.sourceId,
            mangaId: manga.id,
            lang: manga.langFilter,
            scanlators: manga.scanlatorFilter,
            context: context
        ) == 0 {
            return true
        }
        // source is missing
        if SourceManager.shared.source(for: manga.sourceId) == nil {
            return true
        }

        if !excludedCategories.isEmpty {
            // check if excluded via category
            let categories = CoreDataManager.shared.getCategories(
                sourceId: manga.sourceId,
                mangaId: manga.id,
                context: context
            ).compactMap { $0.title }

            if !categories.isEmpty {
                if excludedCategories.contains(where: categories.contains) {
                    return true
                }
            }
        }

        return false
    }

    private func doLibraryRefresh(
        category: String?,
        skipReachabilityCheck: Bool,
        forceAll: Bool,
        task: ProgressReporting? = nil,
        refreshStarted: (() async -> Void)? = nil
    ) async {
        // make sure user agent and sources have loaded before doing library refresh
        _ = await UserAgentProvider.shared.getUserAgent()
        await SourceManager.shared.waitForSourcesLoad()

        // process failed tracker updates first
        await TrackerManager.shared.processPendingUpdates()

        // fetch all library items from db
        let allManga = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getLibraryManga(category: category, context: context).compactMap { $0.manga?.toManga() }
        }

        // ensure there are manga to update
        guard !allManga.isEmpty else {
            return
        }

        // check if connected to wi-fi
        if
            !skipReachabilityCheck,
            UserDefaults.standard.bool(forKey: "Library.updateOnlyOnWifi"),
            Reachability.getConnectionType() != .wifi
        {
            return
        }

        let skipOptions = forceAll ? [] : UserDefaults.standard.stringArray(forKey: "Library.skipTitles") ?? []
        let excludedCategories = forceAll ? [] : (UserDefaults.standard.stringArray(forKey: "Library.excludedUpdateCategories") ?? [])
            .filter { $0 != category }
        let updateMetadata = forceAll || UserDefaults.standard.bool(forKey: "Library.refreshMetadata")

        await refreshStarted?()

        // filter items that we should skip
        let filteredManga = await CoreDataManager.shared.container.performBackgroundTask { context in
            allManga.filter { manga in
                !self.shouldSkip(
                    manga: manga,
                    options: skipOptions,
                    excludedCategories: excludedCategories,
                    context: context
                )
            }
        }

        let total = filteredManga.count
        var completed = 0
        var failed = 0
        task?.progress.totalUnitCount = Int64(total)
        task?.progress.completedUnitCount = 0

#if !os(macOS)
        if #available(iOS 26.0, *),
           let task = task as? BGContinuedProcessingTask
        {
            task.updateTitle(
                NSLocalizedString("REFRESHING_LIBRARY"),
                subtitle: String(
                    format: NSLocalizedString("%i_OF_%i"),
                    0,
                    total
                )
            )
        }
#endif

#if !os(macOS)
        let isBackground = await UIApplication.shared.applicationState != .active
#else
        let isBackground = false
#endif
        let notificationsEnabled = isBackground && NotificationManager.shared.isEnabled()
        var pendingNotifications: [NotificationManager.NewChaptersSummary] = []
        var discoveredChapterCount = 0

        await NotificationManager.shared.beginProgress(
            .libraryUpdate,
            total: total,
            detail: String(
                format: NSLocalizedString("%i_OF_%i"),
                0,
                total
            )
        )

        var newDetails: [MangaIdentifier: AidokuRunner.Manga] = [:]
        let progress = Progress(totalUnitCount: Int64(total))

        // Source requests are network-bound. The old updater awaited each title
        // serially despite already defining a concurrency limit. Fetch bounded
        // batches in parallel, then persist each batch with one Core Data context
        // and one save instead of creating/saving a context per title.
        for batch in filteredManga.chunked(into: Self.maxConcurrentLibraryUpdateTasks) {
            guard !Task.isCancelled else { break }

            let requests = batch.map { manga in
                (
                    identifier: manga.identifier,
                    manga: manga.toNew(),
                    source: SourceManager.shared.source(for: manga.sourceId)
                )
            }
            let batchResults = await withTaskGroup(
                of: (MangaIdentifier, AidokuRunner.Manga?).self,
                returning: [(MangaIdentifier, AidokuRunner.Manga?)].self
            ) { group in
                for request in requests {
                    group.addTask {
                        guard let source = request.source else {
                            return (request.identifier, nil)
                        }
                        let updated = try? await source.getMangaUpdate(
                            manga: request.manga,
                            needsDetails: updateMetadata,
                            needsChapters: true
                        )
                        return (request.identifier, updated)
                    }
                }

                var results: [(MangaIdentifier, AidokuRunner.Manga?)] = []
                results.reserveCapacity(requests.count)
                for await result in group {
                    results.append(result)
                    completed += 1
                    if result.1 == nil { failed += 1 }
                    progress.completedUnitCount = Int64(completed)
                    updateLibraryRefreshProgress(progress)
                }
                return results
            }

            let successfulResults: [(
                identifier: MangaIdentifier,
                manga: AidokuRunner.Manga
            )] = batchResults.compactMap {
                guard let manga = $0.1 else { return nil }
                return (identifier: $0.0, manga: manga)
            }
            guard !successfulResults.isEmpty else { continue }

            if updateMetadata {
                for result in successfulResults {
                    newDetails[result.identifier] = result.manga
                }
            }

            let summaries = await CoreDataManager.shared.container.performBackgroundTask { context in
                var summaries: [NotificationManager.NewChaptersSummary] = []
                for result in successfulResults {
                    let identifier = result.identifier
                    let newManga = result.manga
                    guard
                        let libraryObject = CoreDataManager.shared.getLibraryManga(
                            sourceId: identifier.sourceKey,
                            mangaId: identifier.mangaKey,
                            context: context
                        ),
                        let mangaObject = libraryObject.manga
                    else {
                        continue
                    }

                    // update details
                    if updateMetadata {
                        mangaObject.load(from: newManga)
                    }

                    // update chapters
                    guard let chapters = newManga.chapters, !chapters.isEmpty else { continue }

                    let newChapters = CoreDataManager.shared.setChapters(
                        chapters,
                        sourceId: identifier.sourceKey,
                        mangaId: identifier.mangaKey,
                        context: context
                    )
                    var notifiableCount = 0
                    if !newChapters.isEmpty {
                        // add manga updates
                        let scanlatorFilter = mangaObject.scanlatorFilter ?? []
                        for chapter in newChapters
                        where
                            (mangaObject.langFilter == nil || chapter.lang == mangaObject.langFilter)
                            && (scanlatorFilter.isEmpty || scanlatorFilter.contains(chapter.scanlator ?? ""))
                        {
                            CoreDataManager.shared.createMangaUpdate(
                                sourceId: identifier.sourceKey,
                                mangaId: identifier.mangaKey,
                                chapterObject: chapter,
                                context: context
                            )
                            notifiableCount += 1
                        }
                        libraryObject.lastChapter = chapters.compactMap { $0.dateUploaded }.max()
                        libraryObject.lastUpdatedChapters = Date.now
                    }

                    if updateMetadata || !newChapters.isEmpty {
                        libraryObject.lastUpdated = Date.now
                    }

                    guard notifiableCount > 0 else { continue }
                    summaries.append(
                        NotificationManager.NewChaptersSummary(
                            mangaIdentifier: identifier,
                            mangaTitle: mangaObject.title,
                            chapterCount: notifiableCount
                        )
                    )
                }

                if context.hasChanges {
                    do {
                        try context.save()
                    } catch {
                        LogManager.logger.error(
                            "Unable to save a library update batch: \(error.localizedDescription)"
                        )
                    }
                }
                return summaries
            }

            discoveredChapterCount += summaries.reduce(0) { $0 + $1.chapterCount }
            if notificationsEnabled {
                pendingNotifications.append(contentsOf: summaries)
            }
        }

        if notificationsEnabled, !pendingNotifications.isEmpty {
            await NotificationManager.shared.notifyNewChapters(pendingNotifications)
        }

        if updateMetadata {
            for mangaItem in filteredManga {
                guard let newInfo = newDetails[mangaItem.identifier] else { continue }
                mangaItem.load(from: newInfo.toOld())
            }
        }

        let cancelled = Task.isCancelled
        if !cancelled {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "Library.lastUpdated")
        }
        let completionSummary: String
        if discoveredChapterCount > 0 {
            completionSummary = String(
                format: NSLocalizedString(
                    "LIBRARY_UPDATE_NEW_CHAPTERS_FORMAT",
                    value: "%d new chapters found. %d of %d titles updated.",
                    comment: "Library update completion notification body"
                ),
                discoveredChapterCount,
                completed - failed,
                total
            )
        } else if failed > 0 {
            completionSummary = String(
                format: NSLocalizedString(
                    "LIBRARY_UPDATE_FAILURES_FORMAT",
                    value: "%d of %d titles updated; %d could not be updated.",
                    comment: "Library update completion notification body with failures"
                ),
                completed - failed,
                total,
                failed
            )
        } else {
            completionSummary = String(
                format: NSLocalizedString(
                    "LIBRARY_UPDATE_COMPLETE_FORMAT",
                    value: "%d titles checked. No new chapters found.",
                    comment: "Library update completion notification body"
                ),
                completed
            )
        }
        await NotificationManager.shared.finishProgress(
            .libraryUpdate,
            success: !cancelled,
            summary: completionSummary
        )
    }

    private func updateLibraryRefreshProgress(_ progress: Progress) {
        libraryRefreshProgressTask?.cancel()
        libraryRefreshProgressTask = Task {
            // buffer progress updates by 100ms
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            await onLibraryRefreshProgress?(progress)
            await NotificationManager.shared.updateProgress(
                .libraryUpdate,
                completed: Double(progress.completedUnitCount),
                total: Int(progress.totalUnitCount),
                detail: String(
                    format: NSLocalizedString("%i_OF_%i"),
                    Int(progress.completedUnitCount),
                    Int(progress.totalUnitCount)
                )
            )
        }
    }
}

// MARK: - Detail Editing
extension MangaManager {
    // sets uploaded cover image and returns the new cover url
    func setCover(manga: AidokuRunner.Manga, cover: PlatformImage) async -> String? {
        if manga.isLocal() {
            return await LocalFileManager.shared.setCover(for: manga.key, image: cover)
        }

        // upload cover image to Documents/Covers/id.png
        let documentsDirectory = FileManager.default.documentDirectory
        let targetDirectory = documentsDirectory.appendingPathComponent("Covers")
        let ext = if #available(iOS 17.0, *) {
            "heic"
        } else {
            "png"
        }
        var targetUrl = targetDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        while targetUrl.exists {
            targetUrl = targetDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        }
        targetDirectory.createDirectory()
        do {
            let data = if #available(iOS 17.0, *) {
#if !os(macOS)
                cover.heicData()
#else
                cover.pngData()
#endif
            } else {
                cover.pngData()
            }
            try data?.write(to: targetUrl)
        } catch {
            LogManager.logger.error("MangaManager.setMangaCover: \(error.localizedDescription)")
            return nil
        }

        // set cover in coredata
        let coverUrl = "aidoku-image:///Covers/\(targetUrl.lastPathComponent)"
        await CoreDataManager.shared.setCover(
            sourceId: manga.sourceKey,
            mangaId: manga.key,
            coverUrl: coverUrl
        )

        return coverUrl
    }

    func resetCover(manga: AidokuRunner.Manga) async -> String? {
        guard let source = SourceManager.shared.source(for: manga.sourceKey) else { return nil }

        // fetch new manga details (for cover)
        let newManga = try? await source.getMangaUpdate(
            manga: manga,
            needsDetails: true,
            needsChapters: false
        )

        guard let cover = newManga?.cover else { return nil }

        // set new cover and get old cover url
        let originalCover = await CoreDataManager.shared.setCover(
            sourceId: manga.sourceKey,
            mangaId: manga.key,
            coverUrl: cover,
            original: true
        )

        // if the original cover is an aidoku image, remove it
        if originalCover != cover, let originalCover, let url = URL(string: originalCover)?.toAidokuFileUrl() {
            url.removeItem()
        }

        return cover
    }
}

// MARK: Migration
extension MangaManager {
    func migrate(
        copy: Bool,
        fromSeries: [AidokuRunner.Manga],
        toSeries: [MangaIdentifier: AidokuRunner.Manga?],
        withChapters: [MangaIdentifier: [AidokuRunner.Chapter]] = [:],
        progressReport: ((Float) -> Void)? = nil
    ) async {
        let newDetails = await fetchNewDetails(
            fromSeries: fromSeries,
            toSeries: toSeries,
            withChapters: withChapters,
            progressReport: { counter in
                if let progressReport {
                    progressReport(Float(counter) / Float(fromSeries.count * 2))
                }
            }
        )

        await withTaskGroup(of: (from: AidokuRunner.Manga, to: AidokuRunner.Manga)?.self) { group in
            let batchSize = 10
            var counter = fromSeries.count

            for i in stride(from: 0, to: fromSeries.count, by: batchSize) {
                let batch = Array(fromSeries[i..<min(i + batchSize, fromSeries.count)])

                for oldManga in batch {
                    group.addTask {
                        guard
                            let details = newDetails[oldManga.key]
                        else { return nil }

                        let newManga = details.0
                        let newChapters = details.1

                        return await Self.migrate(copy: copy, from: oldManga, to: newManga, withChapters: newChapters)
                    }
                }

                for await result in group {
                    counter += 1
                    if let progressReport {
                        progressReport(Float(counter) / Float(fromSeries.count * 2))
                    }
                    if let result {
                        if !copy {
                            await TrackerManager.shared.bindEnhancedTrackers(manga: result.to)
                            NotificationCenter.default.post(name: .migratedManga, object: result)
                        }
                    }
                }
            }
        }
    }

    private static func migrate(
        copy: Bool,
        from oldManga: AidokuRunner.Manga,
        to newManga: AidokuRunner.Manga,
        withChapters newChapters: [AidokuRunner.Chapter],
    ) async -> (AidokuRunner.Manga, AidokuRunner.Manga)? {
        // migrate settings
        if let readingMode = UserDefaults.standard.string(forKey: "Reader.readingMode.\(oldManga.identifier)") {
            UserDefaults.standard.set(readingMode, forKey: "Reader.readingMode.\(newManga.identifier)")
            if !copy {
                UserDefaults.standard.removeObject(forKey: "Reader.readingMode.\(oldManga.identifier)")
            }
        }

        // add new item to library if copying
        if copy {
            let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
                let storedNewManga = CoreDataManager.shared.getManga(
                    sourceId: newManga.sourceKey,
                    mangaId: newManga.key,
                    context: context
                )
                guard let storedNewManga else {
                    return false // add to library
                }
                // update details
                storedNewManga.load(from: newManga)
                // update chapters
                CoreDataManager.shared.setChapters(
                    newChapters,
                    sourceId: newManga.sourceKey,
                    mangaId: newManga.key,
                    context: context
                )
                return true
            }
            if !inLibrary {
                await MangaManager.shared.addToLibrary(
                    manga: newManga,
                    chapters: newChapters
                )
            }
        }

        // migrate/copy data
        return await CoreDataManager.shared.container.performBackgroundTask { context in
            do {
                // update manga object in library with new data
                // remove old entry if the new one already exists in library
                if !copy {
                    var mangaObjectToUpdate: MangaObject?

                    // new is already in library
                    if newManga.key != oldManga.key, let storedNewManga = CoreDataManager.shared.getManga(
                        sourceId: newManga.sourceKey,
                        mangaId: newManga.key,
                        context: context
                    ) {
                        // update the object in the library with the new details we fetched already
                        mangaObjectToUpdate = storedNewManga
                        // remove old entry
                        CoreDataManager.shared.removeManga(
                            sourceId: oldManga.sourceKey,
                            mangaId: oldManga.key,
                            context: context
                        )
                    } else {
                        // get existing old object to replace data with new details
                        mangaObjectToUpdate = CoreDataManager.shared.getManga(
                            sourceId: oldManga.sourceKey,
                            mangaId: oldManga.key,
                            context: context
                        )
                    }

                    mangaObjectToUpdate?.load(from: newManga)
                }

                // migrate history
                let storedOldHistory = CoreDataManager.shared.getHistoryForManga(
                    sourceId: oldManga.sourceKey,
                    mangaId: oldManga.key,
                    context: context
                )

                var maxChapterRead = storedOldHistory
                    .compactMap { $0.chapter?.chapter != nil ? $0.chapter : nil }
                    .max { $0.chapter!.decimalValue < $1.chapter!.decimalValue }?
                    .chapter?.floatValue

                if maxChapterRead == nil || maxChapterRead == -1 {
                    // try finding max volume read instead, in case of no chapters
                    maxChapterRead = storedOldHistory
                        .compactMap { $0.chapter?.volume != nil ? $0.chapter : nil }
                        .max { $0.volume!.decimalValue < $1.volume!.decimalValue }?
                        .volume?.floatValue
                }

                // remove old chapters and history
                if !copy {
                    CoreDataManager.shared.removeChapters(
                        sourceId: oldManga.sourceKey,
                        mangaId: oldManga.key,
                        context: context
                    )

                    CoreDataManager.shared.removeHistory(
                        sourceId: oldManga.sourceKey,
                        mangaId: oldManga.key,
                        context: context
                    )

                    // store new chapters
                    CoreDataManager.shared.setChapters(
                        newChapters,
                        sourceId: newManga.sourceKey,
                        mangaId: newManga.key,
                        context: context
                    )
                }

                // mark new chapters as read
                if let maxChapterRead {
                    var chaptersToMark = newChapters.filter({ $0.chapterNumber ?? Float.greatestFiniteMagnitude <= maxChapterRead })
                    if chaptersToMark.isEmpty {
                        // fall back to using volume numbers instead, in case the source we're migrating to uses volumes
                        chaptersToMark = newChapters.filter({ $0.volumeNumber ?? Float.greatestFiniteMagnitude <= maxChapterRead })
                    }
                    if !chaptersToMark.isEmpty {
                        CoreDataManager.shared.setCompleted(
                            sourceId: newManga.sourceKey,
                            mangaId: newManga.key,
                            chapterIds: chaptersToMark.map { $0.key },
                            context: context
                        )
                    }
                }

                // migrate trackers
                let trackItems = CoreDataManager.shared.getTracks(
                    sourceId: oldManga.sourceKey,
                    mangaId: oldManga.key,
                    context: context
                )

                for item in trackItems {
                    guard
                        let trackId = item.id,
                        let trackerId = item.trackerId,
                        !CoreDataManager.shared.hasTrack(
                            trackerId: trackerId,
                            sourceId: newManga.sourceKey,
                            mangaId: newManga.key,
                            context: context
                        ),
                        let tracker = TrackerManager.getTracker(id: trackerId),
                        tracker.canRegister(sourceKey: newManga.sourceKey, mangaKey: newManga.key)
                    else {
                        if !copy && newManga.identifier != oldManga.identifier {
                            context.delete(item)
                        }
                        continue
                    }

                    if copy {
                        CoreDataManager.shared.createTrack(
                            id: trackId,
                            trackerId: trackerId,
                            sourceId: newManga.sourceKey,
                            mangaId: newManga.key,
                            title: item.title,
                            context: context
                        )
                    } else {
                        item.sourceId = newManga.sourceKey
                        item.mangaId = newManga.key
                    }
                }

                try context.save()

                return (from: oldManga, to: newManga)
            } catch {
                LogManager.logger.error("Error migrating manga \(oldManga.key): \(error)")
                return nil
            }
        }
    }

    private func fetchNewDetails(
        fromSeries: [AidokuRunner.Manga],
        toSeries: [MangaIdentifier: AidokuRunner.Manga?],
        withChapters: [MangaIdentifier: [AidokuRunner.Chapter]],
        progressReport: (Int) -> Void
    ) async -> [String: (AidokuRunner.Manga, [AidokuRunner.Chapter])] {
        await withTaskGroup(
            of: (String, AidokuRunner.Manga, [AidokuRunner.Chapter])?.self,
            returning: [String: (AidokuRunner.Manga, [AidokuRunner.Chapter])].self
        ) { group in
            let batchSize = 10
            var ret: [String: (AidokuRunner.Manga, [AidokuRunner.Chapter])] = [:]
            var counter = 0

            for i in stride(from: 0, to: fromSeries.count, by: batchSize) {
                let batch = Array(fromSeries[i..<min(i + batchSize, fromSeries.count)])

                for oldManga in batch {
                    group.addTask {
                        guard
                            let newManga = toSeries[oldManga.identifier],
                            let newManga,
                            let source = SourceManager.shared.source(for: newManga.sourceKey)
                        else { return nil }

                        let newChapters = withChapters[oldManga.identifier]

                        let updatedManga = try? await source.getMangaUpdate(
                            manga: newManga,
                            needsDetails: true,
                            needsChapters: newChapters == nil
                        )

                        let mangaDetails = updatedManga ?? newManga
                        let chapters = newChapters ?? updatedManga?.chapters ?? []

                        return (oldManga.key, mangaDetails, chapters)
                    }
                }

                // wait for all results in batch to finish before continuing
                for await result in group {
                    counter += 1
                    progressReport(counter)
                    if let result {
                        ret[result.0] = (result.1, result.2)
                    }
                }
            }

            return ret
        }
    }
}
