import XCTest
@testable import Ahoge

@MainActor
final class ChapterNavigatorTests: XCTestCase {
    private var repo: LibraryRepository!

    /// Chapters newest first, as a source lists them.
    private func manga(_ chapters: [SourceChapter]) throws -> LibraryManga {
        repo = try LibraryRepository.inMemory()
        let manga = repo.upsert(sourceId: "s", url: "/m", title: "M", cover: "")
        repo.applyChapters(chapters, to: manga)
        return manga
    }

    private func chapter(_ url: String, _ number: Double, _ scanlator: String? = nil) -> SourceChapter {
        SourceChapter(url: url, name: url, number: number, date: nil, scanlator: scanlator)
    }

    private func find(_ manga: LibraryManga, _ url: String) throws -> ChapterRecord {
        try XCTUnwrap(manga.chapters.first { $0.url == url })
    }

    private func navigator(_ manga: LibraryManga, display: ChapterDisplay = ChapterDisplay(), excluded: Set<String> = [], rules: SkipRules) -> ChapterNavigator {
        ChapterNavigator(chapters: manga.chapters, display: display, excludedScanlators: excluded, rules: rules)
    }

    func testSkipRead() throws {
        let manga = try manga([chapter("/4", 4), chapter("/3", 3), chapter("/2", 2), chapter("/1", 1)])
        repo.setRead([try find(manga, "/2")], true)
        let first = try find(manga, "/1")
        XCTAssertEqual(navigator(manga, rules: SkipRules(skipRead: false)).next(after: first)?.url, "/2")
        XCTAssertEqual(navigator(manga, rules: SkipRules(skipRead: true)).next(after: first)?.url, "/3")
        XCTAssertEqual(navigator(manga, rules: SkipRules(skipRead: true)).previous(before: try find(manga, "/3"))?.url, "/1")
    }

    func testSkipFilteredChaptersAndScanlators() throws {
        let manga = try manga([chapter("/4", 4, "A"), chapter("/3", 3, "B"), chapter("/2", 2, "A"), chapter("/1", 1, "A")])
        repo.setRead([try find(manga, "/2")], true)
        let first = try find(manga, "/1")
        let unread = ChapterDisplay(filter: .unread)
        XCTAssertEqual(navigator(manga, display: unread, rules: SkipRules(skipFiltered: true)).next(after: first)?.url, "/3")
        XCTAssertEqual(navigator(manga, display: unread, excluded: ["B"], rules: SkipRules(skipFiltered: true)).next(after: first)?.url, "/4")
        XCTAssertEqual(navigator(manga, display: unread, excluded: ["B"], rules: SkipRules(skipFiltered: false)).next(after: first)?.url, "/2")
    }

    func testSkipDuplicatesStaysWithTheCurrentGroup() throws {
        // Reading order 1A, 1B, 2A, 2B, 3A.
        let manga = try manga([chapter("/3a", 3, "A"), chapter("/2b", 2, "B"), chapter("/2a", 2, "A"), chapter("/1b", 1, "B"), chapter("/1a", 1, "A")])
        let rules = SkipRules(skipDuplicates: true)
        XCTAssertEqual(navigator(manga, rules: rules).next(after: try find(manga, "/1b"))?.url, "/2b")
        XCTAssertEqual(navigator(manga, rules: rules).next(after: try find(manga, "/1a"))?.url, "/2a")
        XCTAssertEqual(navigator(manga, rules: rules).previous(before: try find(manga, "/2b"))?.url, "/1b")
        // Group B has no chapter 3: the first in source order.
        XCTAssertEqual(navigator(manga, rules: rules).next(after: try find(manga, "/2b"))?.url, "/3a")
        // Without the rule, the next chapter in the list, whatever its number.
        XCTAssertEqual(navigator(manga, rules: SkipRules()).next(after: try find(manga, "/1a"))?.url, "/1b")
    }

    func testOrderFollowsTheChapterSort() throws {
        // The source lists an extra out of order; sorted by number it comes between 1 and 2.
        let manga = try manga([chapter("/3", 3), chapter("/1.5", 1.5), chapter("/2", 2), chapter("/1", 1)])
        let byNumber = ChapterDisplay(sort: .number)
        XCTAssertEqual(navigator(manga, display: byNumber, rules: SkipRules()).next(after: try find(manga, "/1"))?.url, "/1.5")
        XCTAssertEqual(navigator(manga, rules: SkipRules()).next(after: try find(manga, "/1"))?.url, "/2")
    }
}
