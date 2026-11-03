import XCTest
@testable import Ahoge

final class LibraryQueryTests: XCTestCase {
    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400) }

    /// A title with `read` read chapters and `unread` unread ones.
    private func title(_ name: String, read: Int = 0, unread: Int = 0, status: String = "ongoing", bookmarked: Int = 0) -> LibraryManga {
        let manga = LibraryManga(sourceId: "en.demo", url: "/m/\(name)", title: name, coverUrl: "")
        manga.status = status
        manga.inLibrary = true
        var states: [ChapterState] = []
        for index in 0..<(read + unread) {
            states.append(ChapterState(url: "/c/\(index)", name: "Ch \(index)", number: Double(index), date: nil, scanlator: nil, read: index < read, lastPageRead: 0, sourceOrder: index))
        }
        manga.chapters = states.map { ChapterRecord(manga: manga, state: $0) }
        for chapter in manga.chapters.prefix(bookmarked) { chapter.bookmark = true }
        manga.refreshUnreadCount()
        return manga
    }

    private func names(_ query: LibraryQuery, _ manga: [LibraryManga], facts: LibraryFacts = LibraryFacts()) -> [String] {
        query.apply(to: manga, facts: facts).map(\.title)
    }

    // MARK: Filters

    func testUnreadIncludeAndExclude() {
        let all = [title("A", unread: 2), title("B", read: 3), title("C")]
        var query = LibraryQuery()
        query.filters.unread = .include
        XCTAssertEqual(names(query, all), ["A"])
        query.filters.unread = .exclude
        XCTAssertEqual(names(query, all), ["B", "C"])
    }

    func testStartedIncludeAndExclude() {
        let begun = title("Begun", unread: 2)
        begun.chapters[0].lastPageRead = 4
        let all = [begun, title("Done", read: 1), title("Fresh", unread: 2)]
        var query = LibraryQuery()
        query.filters.started = .include
        XCTAssertEqual(names(query, all), ["Begun", "Done"])
        query.filters.started = .exclude
        XCTAssertEqual(names(query, all), ["Fresh"])
    }

    func testDownloadedUsesTheFacts() {
        let all = [title("A"), title("B"), title("C")]
        let facts = LibraryFacts(downloadedCount: { $0.hasSuffix("/m/B") ? 2 : 0 })
        var query = LibraryQuery()
        query.filters.downloaded = .include
        XCTAssertEqual(names(query, all, facts: facts), ["B"])
        query.filters.downloaded = .exclude
        XCTAssertEqual(names(query, all, facts: facts), ["A", "C"])
    }

    func testBookmarkedFromChapters() {
        let all = [title("A", unread: 2, bookmarked: 1), title("B", unread: 2)]
        var query = LibraryQuery()
        query.filters.bookmarked = .include
        XCTAssertEqual(names(query, all), ["A"])
        query.filters.bookmarked = .exclude
        XCTAssertEqual(names(query, all), ["B"])
    }

    func testBookmarkedFromTheFacts() {
        let all = [title("A"), title("B")]
        let facts = LibraryFacts(bookmarkedCount: { $0.hasSuffix("/m/A") ? 1 : 0 })
        var query = LibraryQuery()
        query.filters.bookmarked = .include
        XCTAssertEqual(names(query, all, facts: facts), ["A"])
    }

    func testCompletedIncludeAndExclude() {
        let all = [title("A", status: "completed"), title("B", status: "ongoing")]
        var query = LibraryQuery()
        query.filters.completed = .include
        XCTAssertEqual(names(query, all), ["A"])
        query.filters.completed = .exclude
        XCTAssertEqual(names(query, all), ["B"])
    }

    func testCustomIntervalIncludeAndExclude() {
        let slow = title("Slow")
        slow.updateInterval = 7
        let all = [slow, title("Smart")]
        var query = LibraryQuery()
        query.filters.customInterval = .include
        XCTAssertEqual(names(query, all), ["Slow"])
        query.filters.customInterval = .exclude
        XCTAssertEqual(names(query, all), ["Smart"])
    }

    func testFiltersCombine() {
        let all = [title("A", unread: 1, status: "completed"), title("B", unread: 1), title("C", status: "completed")]
        var query = LibraryQuery()
        query.filters.unread = .include
        query.filters.completed = .include
        XCTAssertEqual(names(query, all), ["A"])
    }

    func testFiltersRoundTripThroughTheirStoredForm() {
        var filters = LibraryFilters()
        XCTAssertEqual(filters.stored, "")
        filters.unread = .include
        filters.completed = .exclude
        XCTAssertEqual(LibraryFilters(stored: filters.stored), filters)
        XCTAssertFalse(LibraryFilters(stored: "not json").isActive)
    }

    // MARK: Sorts

    func testTitleSortIgnoresCaseBothWays() {
        let all = [title("banana"), title("Cherry"), title("apple")]
        var query = LibraryQuery()
        XCTAssertEqual(names(query, all), ["apple", "banana", "Cherry"])
        query.sort = LibrarySort(key: .title, ascending: false)
        XCTAssertEqual(names(query, all), ["Cherry", "banana", "apple"])
    }

    func testTotalChaptersSort() {
        let all = [title("A", unread: 3), title("B", unread: 1), title("C", read: 2)]
        var query = LibraryQuery()
        query.sort = LibrarySort(key: .totalChapters, ascending: true)
        XCTAssertEqual(names(query, all), ["B", "C", "A"])
        query.sort = LibrarySort(key: .totalChapters, ascending: false)
        XCTAssertEqual(names(query, all), ["A", "C", "B"])
    }

    func testLastReadSortPutsNeverReadFirstWhenAscending() {
        let a = title("A")
        a.lastReadAt = day(5)
        let b = title("B")
        b.lastReadAt = day(2)
        var query = LibraryQuery()
        query.sort = LibrarySort(key: .lastRead, ascending: true)
        XCTAssertEqual(names(query, [a, b, title("Never")]), ["Never", "B", "A"])
        query.sort = LibrarySort(key: .lastRead, ascending: false)
        XCTAssertEqual(names(query, [a, b, title("Never")]), ["A", "B", "Never"])
    }

    func testLastUpdateCheckSort() {
        let a = title("A")
        a.lastChapterFetch = day(9)
        let b = title("B")
        b.lastChapterFetch = day(3)
        var query = LibraryQuery()
        query.sort = LibrarySort(key: .lastUpdateCheck, ascending: false)
        XCTAssertEqual(names(query, [b, a]), ["A", "B"])
    }

    func testUnreadCountSortBreaksTiesByTitle() {
        let all = [title("C", unread: 2), title("A", unread: 2), title("B", unread: 5)]
        var query = LibraryQuery()
        query.sort = LibrarySort(key: .unreadCount, ascending: false)
        XCTAssertEqual(names(query, all), ["B", "A", "C"])
        query.sort = LibrarySort(key: .unreadCount, ascending: true)
        XCTAssertEqual(names(query, all), ["A", "C", "B"])
    }

    func testLatestChapterSortUsesTheNewestUpload() {
        let a = title("A", unread: 2)
        a.chapters[0].dateUpload = day(1)
        a.chapters[1].dateUpload = day(8)
        let b = title("B", unread: 1)
        b.chapters[0].dateUpload = day(4)
        var query = LibraryQuery()
        query.sort = LibrarySort(key: .latestChapter, ascending: false)
        XCTAssertEqual(names(query, [b, a]), ["A", "B"])
        query.sort = LibrarySort(key: .latestChapter, ascending: true)
        XCTAssertEqual(names(query, [a, b]), ["B", "A"])
    }

    func testChapterFetchDateSortUsesTheNewestFetch() {
        let a = title("A", unread: 1)
        a.chapters[0].dateFetch = day(2)
        let b = title("B", unread: 2)
        b.chapters[0].dateFetch = day(1)
        b.chapters[1].dateFetch = day(6)
        var query = LibraryQuery()
        query.sort = LibrarySort(key: .chapterFetchDate, ascending: false)
        XCTAssertEqual(names(query, [a, b]), ["B", "A"])
    }

    func testDateAddedSort() {
        let a = title("A")
        a.dateAdded = day(1)
        let b = title("B")
        b.dateAdded = day(7)
        var query = LibraryQuery()
        query.sort = LibrarySort(key: .dateAdded, ascending: false)
        XCTAssertEqual(names(query, [a, b]), ["B", "A"])
        query.sort = LibrarySort(key: .dateAdded, ascending: true)
        XCTAssertEqual(names(query, [b, a]), ["A", "B"])
    }

    func testRandomIsStableForASeedAndIgnoresDirection() {
        let all = (0..<12).map { title("T\($0)") }
        var query = LibraryQuery()
        query.sort = LibrarySort(key: .random, ascending: true)
        let facts = LibraryFacts(randomSeed: 42)
        let first = names(query, all, facts: facts)
        XCTAssertEqual(names(query, all.reversed(), facts: facts), first)
        query.sort = LibrarySort(key: .random, ascending: false)
        XCTAssertEqual(names(query, all, facts: facts), first)
        XCTAssertEqual(Set(first), Set(all.map(\.title)))
        XCTAssertNotEqual(names(query, all, facts: LibraryFacts(randomSeed: 43)), first)
    }

    // MARK: Search

    func testSearchMatchesAuthorArtistAndGenre() {
        let a = title("Alpha")
        a.author = "Oda"
        let b = title("Beta")
        b.artist = "Toriyama"
        let c = title("Gamma")
        c.genres = ["Action", "Comedy"]
        var query = LibraryQuery()
        query.search = "oda"
        XCTAssertEqual(names(query, [a, b, c]), ["Alpha"])
        query.search = "TORI"
        XCTAssertEqual(names(query, [a, b, c]), ["Beta"])
        query.search = "comedy"
        XCTAssertEqual(names(query, [a, b, c]), ["Gamma"])
    }

    func testGenrePrefixSearchesGenresOnly() {
        let a = title("Action Heroes")
        let b = title("Quiet Days")
        b.genres = ["Action"]
        var query = LibraryQuery()
        query.search = "genre:action"
        XCTAssertEqual(names(query, [a, b]), ["Quiet Days"])
    }

    // MARK: Stored sort

    func testSortStoredForm() {
        XCTAssertEqual(LibrarySort(key: .unreadCount, ascending: false).stored, "unreadCount:desc")
        XCTAssertEqual(LibrarySort(stored: "lastRead:asc"), LibrarySort(key: .lastRead, ascending: true))
        XCTAssertEqual(LibrarySort(stored: "Title"), LibrarySort(key: .title, ascending: true))
        XCTAssertEqual(LibrarySort(stored: "Date added"), LibrarySort(key: .dateAdded, ascending: false))
        XCTAssertNil(LibrarySort(stored: "nonsense"))
    }

    func testTappingTheSameKeyFlipsAndAnotherStartsAscending() {
        let sort = LibrarySort(key: .title, ascending: true)
        XCTAssertEqual(sort.tapping(.title), LibrarySort(key: .title, ascending: false))
        XCTAssertEqual(sort.tapping(.lastRead), LibrarySort(key: .lastRead, ascending: true))
    }
}
