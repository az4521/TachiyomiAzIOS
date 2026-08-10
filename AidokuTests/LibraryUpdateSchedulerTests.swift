@testable import Aidoku
import Foundation
import Testing

struct LibraryUpdateSchedulerTests {
    @Test func supportedIntervals() {
        #expect(MangaManager.libraryUpdateInterval(for: "12hours") == 43_200)
        #expect(MangaManager.libraryUpdateInterval(for: "daily") == 86_400)
        #expect(MangaManager.libraryUpdateInterval(for: "2days") == 172_800)
        #expect(MangaManager.libraryUpdateInterval(for: "weekly") == 604_800)
    }

    @Test func disabledAndUnknownIntervalsDoNotSchedule() {
        #expect(MangaManager.libraryUpdateInterval(for: "never") == nil)
        #expect(MangaManager.libraryUpdateInterval(for: nil) == nil)
        #expect(MangaManager.libraryUpdateInterval(for: "unexpected") == nil)
    }

    @Test func nextRefreshDateUsesSelectedInterval() {
        let referenceDate = Date(timeIntervalSince1970: 1_000_000)

        #expect(
            MangaManager.nextLibraryRefreshDate(after: referenceDate, intervalValue: "daily")
                == referenceDate.addingTimeInterval(86_400)
        )
        #expect(
            MangaManager.nextLibraryRefreshDate(after: referenceDate, intervalValue: "never")
                == nil
        )
    }

    @Test func progressNotificationBodyShowsAndClampsProgress() {
        #expect(
            NotificationManager.progressBody(
                completed: 5,
                total: 10,
                detail: "5 of 10"
            ) == "█████░░░░░ 50%\n5 of 10"
        )
        #expect(
            NotificationManager.progressBody(completed: -1, total: 10)
                == "░░░░░░░░░░ 0%"
        )
        #expect(
            NotificationManager.progressBody(completed: 12, total: 10)
                == "██████████ 100%"
        )
    }

    @Test func libraryRefreshProgressFormatsCountsAndClampsValues() {
        let halfway = LibraryRefreshProgress(completed: 5, total: 10)
        #expect(halfway.localizedDetail == "5 of 10")
        #expect(halfway.fractionCompleted == 0.5)

        let belowZero = LibraryRefreshProgress(completed: -1, total: 10)
        #expect(belowZero.completed == 0)
        #expect(belowZero.localizedDetail == "0 of 10")
        #expect(belowZero.fractionCompleted == 0)

        let aboveTotal = LibraryRefreshProgress(completed: 12, total: 10)
        #expect(aboveTotal.completed == 10)
        #expect(aboveTotal.localizedDetail == "10 of 10")
        #expect(aboveTotal.fractionCompleted == 1)
    }

    @Test func zeroTitleLibraryRefreshHasStableProgress() {
        let progress = LibraryRefreshProgress(completed: 0, total: 0)
        #expect(progress.localizedDetail == "0 of 0")
        #expect(progress.fractionCompleted == 0)
    }

    @Test func emptyScanlatorFilterDoesNotExcludeEveryChapter() {
        #expect(CoreDataManager.normalizedScanlatorFilter(nil) == nil)
        #expect(CoreDataManager.normalizedScanlatorFilter([]) == nil)
        #expect(CoreDataManager.normalizedScanlatorFilter(["Group"]) == ["Group"])
    }
}
