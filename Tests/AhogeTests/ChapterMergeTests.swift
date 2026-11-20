import XCTest
@testable import Ahoge

final class ChapterMergeTests: XCTestCase {
    private func fetched(_ url: String, _ number: Double, date: Double? = 1_704_412_800_000) -> SourceChapter {
        SourceChapter(url: url, name: "Ch \(number)", number: number, date: date, scanlator: nil)
    }

    func testKeepsReadStateAndAssignsSourceOrder() {
        let existing = [
            ChapterState(url: "/c1", name: "old", number: 1, date: nil, scanlator: nil, read: true, lastPageRead: 9, sourceOrder: 0),
        ]
        let merged = ChapterMerge.merge(existing: existing, fetched: [fetched("/c2", 2), fetched("/c1", 1)])
        XCTAssertEqual(merged.map(\.url), ["/c2", "/c1"])
        XCTAssertEqual(merged.map(\.sourceOrder), [0, 1])
        XCTAssertEqual(merged[1].read, true)
        XCTAssertEqual(merged[1].lastPageRead, 9)
        XCTAssertEqual(merged[1].name, "Ch 1.0")
        XCTAssertEqual(merged[0].read, false)
        XCTAssertEqual(merged[0].date, Date(timeIntervalSince1970: 1_704_412_800))
    }

    func testDropsDuplicatesAndMissingChapters() {
        let existing = [ChapterState(url: "/gone", name: "x", number: 1, date: nil, scanlator: nil, read: true, lastPageRead: 0, sourceOrder: 0)]
        let merged = ChapterMerge.merge(existing: existing, fetched: [fetched("/a", 2), fetched("/a", 2), fetched("/b", 1, date: nil)])
        XCTAssertEqual(merged.map(\.url), ["/a", "/b"])
        XCTAssertNil(merged[1].date)
    }

    func testDateFetchMarksOnlyNewChapters() {
        let then = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 2_000)
        let existing = [
            ChapterState(url: "/c1", name: "1", number: 1, date: nil, scanlator: nil, read: false, lastPageRead: 0, sourceOrder: 0, dateFetch: then),
            ChapterState(url: "/c0", name: "0", number: 0, date: nil, scanlator: nil, read: false, lastPageRead: 0, sourceOrder: 1, dateFetch: nil),
        ]
        let fetched = [
            SourceChapter(url: "/c2", name: "2", number: 2, date: nil, scanlator: nil),
            SourceChapter(url: "/c1", name: "1", number: 1, date: nil, scanlator: nil),
            SourceChapter(url: "/c0", name: "0", number: 0, date: nil, scanlator: nil),
        ]
        let merged = ChapterMerge.merge(existing: existing, fetched: fetched, now: now)
        XCTAssertEqual(merged.map(\.dateFetch), [now, then, nil])
    }

    private func stored(_ url: String, _ number: Double, scanlator: String? = nil, read: Bool = false, page: Int = 0, dateFetch: Date? = nil) -> ChapterState {
        ChapterState(url: url, name: "x", number: number, date: nil, scanlator: scanlator, read: read, lastPageRead: page, sourceOrder: 0, dateFetch: dateFetch)
    }

    private func source(_ url: String, _ number: Double, scanlator: String? = nil) -> SourceChapter {
        SourceChapter(url: url, name: "Ch", number: number, date: nil, scanlator: scanlator)
    }

    func testURLChangeCarriesReadStateToTheNewURL() {
        let then = Date(timeIntervalSince1970: 1_000)
        let existing = [stored("/old/2", 2, page: 4, dateFetch: then), stored("/old/1", 1, read: true)]
        let fetched = [source("/new/2", 2), source("/new/1", 1)]
        XCTAssertEqual(ChapterMerge.carries(existing: existing, fetched: fetched), ["/old/1": "/new/1", "/old/2": "/new/2"])
        let merged = ChapterMerge.merge(existing: existing, fetched: fetched, now: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(merged.map(\.read), [false, true])
        XCTAssertEqual(merged.map(\.lastPageRead), [4, 0])
        XCTAssertEqual(merged.map(\.dateFetch), [then, nil])
    }

    func testSameNumberCarriesByScanlator() {
        let existing = [stored("/a/1", 1, scanlator: "A"), stored("/b/1", 1, scanlator: "B")]
        let fetched = [source("/y/1", 1, scanlator: "B"), source("/x/1", 1, scanlator: "A")]
        XCTAssertEqual(ChapterMerge.carries(existing: existing, fetched: fetched), ["/a/1": "/x/1", "/b/1": "/y/1"])
    }

    func testAmbiguousNumberDoesNotCarry() {
        let existing = [stored("/a/1", 1, scanlator: "A"), stored("/a2/1", 1, scanlator: "A")]
        XCTAssertEqual(ChapterMerge.carries(existing: existing, fetched: [source("/x/1", 1, scanlator: "A")]), [:])
        XCTAssertEqual(ChapterMerge.carries(existing: [stored("/a/1", 1)], fetched: [source("/x/1", 1, scanlator: "A"), source("/y/1", 1, scanlator: "B")]), [:])
    }

    func testUnnumberedChaptersNeverCarry() {
        let merged = ChapterMerge.merge(existing: [stored("/old/x", -1, read: true)], fetched: [source("/new/x", -1)])
        XCTAssertEqual(ChapterMerge.carries(existing: [stored("/old/x", -1, read: true)], fetched: [source("/new/x", -1)]), [:])
        XCTAssertEqual(merged.map(\.read), [false])
    }

    func testFirstChapterListIsNotAnUpdate() {
        let merged = ChapterMerge.merge(existing: [], fetched: [SourceChapter(url: "/c1", name: "1", number: 1, date: nil, scanlator: nil)], now: Date())
        XCTAssertEqual(merged.map(\.dateFetch), [nil])
    }
}
