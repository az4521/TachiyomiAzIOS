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
}
