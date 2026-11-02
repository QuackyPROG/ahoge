import XCTest
@testable import Ahoge

@MainActor
final class ChapterDisplayTests: XCTestCase {
    private func chapters() throws -> [ChapterRecord] {
        let repo = try LibraryRepository.inMemory()
        let manga = repo.upsert(sourceId: "s", url: "/m", title: "M", cover: "")
        // Source order (newest first): 3, 1.5 (no date), 2, 1 — the source lists an extra out of order.
        let day = 86_400_000.0
        repo.applyChapters([
            SourceChapter(url: "/c/3", name: "Ch 3", number: 3, date: 3 * day, scanlator: nil),
            SourceChapter(url: "/c/1.5", name: "Extra", number: 1.5, date: nil, scanlator: nil),
            SourceChapter(url: "/c/2", name: "Ch 2", number: 2, date: 2 * day, scanlator: nil),
            SourceChapter(url: "/c/1", name: "Ch 1", number: 1, date: 1 * day, scanlator: nil),
        ], to: manga)
        repo.setRead(manga.chapters.filter { $0.url == "/c/1" || $0.url == "/c/2" }, true)
        return manga.chapters
    }

    func testSortsAndFilters() throws {
        let list = try chapters()
        let urls = { (display: ChapterDisplay) in display.apply(to: list).map(\.url) }
        XCTAssertEqual(urls(ChapterDisplay()), ["/c/3", "/c/1.5", "/c/2", "/c/1"])
        XCTAssertEqual(urls(ChapterDisplay(sort: .source, ascending: true)), ["/c/1", "/c/2", "/c/1.5", "/c/3"])
        XCTAssertEqual(urls(ChapterDisplay(sort: .number)), ["/c/3", "/c/2", "/c/1.5", "/c/1"])
        XCTAssertEqual(urls(ChapterDisplay(sort: .date)), ["/c/3", "/c/2", "/c/1", "/c/1.5"])
        XCTAssertEqual(urls(ChapterDisplay(sort: .number, filter: .unread)), ["/c/3", "/c/1.5"])
        XCTAssertEqual(urls(ChapterDisplay(sort: .number, ascending: true, filter: .read)), ["/c/1", "/c/2"])
    }

    func testSavesOnlyNonDefault() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ChapterDisplayTests"))
        defaults.removePersistentDomain(forName: "ChapterDisplayTests")
        XCTAssertEqual(ChapterDisplay.load(for: "k", from: defaults), ChapterDisplay())
        let custom = ChapterDisplay(sort: .date, ascending: true, filter: .unread)
        custom.save(for: "k", to: defaults)
        XCTAssertEqual(ChapterDisplay.load(for: "k", from: defaults), custom)
        ChapterDisplay().save(for: "k", to: defaults)
        XCTAssertNil(defaults.data(forKey: "chapterDisplay.k"))
    }

    func testDescriptionCleanup() {
        let raw = "A hero rises.&nbsp;Tom &amp; Jerry<br>Next line\r\n\r\n\r\n\r\n---\n**Links:**\n- [Official](https://example.com)\n* Raw\n<p>End</p>"
        XCTAssertEqual(
            DescriptionFormatter.clean(raw),
            "A hero rises. Tom & Jerry\nNext line\n\n**Links:**\n• [Official](https://example.com)\n• Raw\nEnd"
        )
        let rendered = DescriptionFormatter.attributed("**Bold** and [link](https://example.com)")
        XCTAssertEqual(String(rendered.characters), "Bold and link")
        XCTAssertEqual(rendered.runs.compactMap { $0.link }.first, URL(string: "https://example.com"))
    }
}
