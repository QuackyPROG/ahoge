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

    func testFirstChapterListIsNotAnUpdate() {
        let merged = ChapterMerge.merge(existing: [], fetched: [SourceChapter(url: "/c1", name: "1", number: 1, date: nil, scanlator: nil)], now: Date())
        XCTAssertEqual(merged.map(\.dateFetch), [nil])
    }
}
