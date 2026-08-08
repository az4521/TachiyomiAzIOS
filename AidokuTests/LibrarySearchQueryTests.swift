@testable import Aidoku
import Testing

struct LibrarySearchQueryTests {
    @Test
    func parsesQuotedAndExcludedTagsWithoutTreatingInternalHyphensAsExclusions() {
        let terms = LibrarySearchQuery(#""Slice of Life" -action x-ray -"Boys Love""#).terms

        #expect(terms == [
            .init(value: "Slice of Life", isExcluded: false),
            .init(value: "action", isExcluded: true),
            .init(value: "x-ray", isExcluded: false),
            .init(value: "Boys Love", isExcluded: true)
        ])
    }

    @Test
    func searchesTitlesAuthorsAndGenreTags() {
        let manga = MangaInfo(
            mangaId: "manga",
            sourceId: "source",
            title: "A Completely Different Title",
            author: "Example Author",
            tags: ["Slice of Life", "X-Ray"]
        )

        #expect(LibrarySearchQuery(#""slice of life""#).matches(manga))
        #expect(LibrarySearchQuery("x-ray").matches(manga))
        #expect(LibrarySearchQuery("example").matches(manga))
    }

    @Test
    func excludedTermsOnlyExcludeMatchingGenreTags() {
        let manga = MangaInfo(
            mangaId: "manga",
            sourceId: "source",
            title: "Action Hero",
            tags: ["Comedy", "Slice of Life"]
        )

        #expect(LibrarySearchQuery("action -drama").matches(manga))
        #expect(!LibrarySearchQuery(#"-"slice of life""#).matches(manga))
    }
}
