import XCTest
import ZIPFoundation
@testable import Ahoge

final class LocalSourceTests: XCTestCase {
    private var directory: URL!
    private var root: URL { directory.appendingPathComponent("Local") }
    private let fm = FileManager.default

    override func setUpWithError() throws {
        directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: directory)
    }

    private func source() -> LocalSource {
        LocalSource(root: root, cache: directory.appendingPathComponent("Cache"))
    }

    private func write(_ path: String, _ text: String = "x") throws {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func testListsSeriesFoldersWithCoverAndDetailsTitle() async throws {
        try write("Beta/Chapter 1/1.jpg")
        try write("Alpha/cover.jpg")
        try write("Alpha/details.json", #"{"title":"Alpha Prime","author":"A","genre":["Action","Drama"],"status":"2"}"#)
        try write("Alpha/Chapter 1/1.jpg")

        let page = try await source().popular(page: 1)

        XCTAssertEqual(page.manga.map(\.url), ["Alpha", "Beta"])
        XCTAssertEqual(page.manga.map(\.title), ["Alpha Prime", "Beta"])
        XCTAssertTrue(page.manga[0].cover.hasSuffix("/Alpha/cover.jpg"))
        XCTAssertEqual(page.manga[1].cover, "")
        XCTAssertFalse(page.hasNextPage)
        let found = try await source().search(query: "prime", page: 1)
        XCTAssertEqual(found.manga.map(\.url), ["Alpha"])
    }

    func testDetailsReadMihonJSON() async throws {
        try write("Alpha/details.json", #"{"title":"Alpha Prime","author":"Au","artist":"Ar","description":"Hello","genre":["Action","Drama"],"status":"1"}"#)

        let details = try await source().details(url: "Alpha")

        XCTAssertEqual(details.title, "Alpha Prime")
        XCTAssertEqual(details.author, "Au")
        XCTAssertEqual(details.artist, "Ar")
        XCTAssertEqual(details.description, "Hello")
        XCTAssertEqual(details.genres, ["Action", "Drama"])
        XCTAssertEqual(details.status, "ongoing")
    }

    func testChaptersAreInNaturalOrderWithParsedNumbers() async throws {
        try write("S/Chapter 10.cbz")
        try write("S/Chapter 2.cbz")
        try write("S/Chapter 1.5/1.jpg")

        let chapters = try await source().chapters(url: "S")

        XCTAssertEqual(chapters.map(\.name), ["Chapter 1.5", "Chapter 2", "Chapter 10"])
        XCTAssertEqual(chapters.map(\.number), [1.5, 2, 10])
        XCTAssertEqual(chapters.map(\.url), ["S/Chapter 1.5", "S/Chapter 2.cbz", "S/Chapter 10.cbz"])
    }

    func testChapterNumberParsing() {
        XCTAssertEqual(LocalSource.chapterNumber(from: "Vol 3 Ch. 12"), 12)
        XCTAssertEqual(LocalSource.chapterNumber(from: "Series 007"), 7)
        XCTAssertEqual(LocalSource.chapterNumber(from: "Extras"), -1)
    }

    func testCBZPagesComeBackInNaturalOrder() async throws {
        let staging = directory.appendingPathComponent("staging")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        for name in ["10.jpg", "2.jpg", "1.jpg"] { try Data(name.utf8).write(to: staging.appendingPathComponent(name)) }
        let series = root.appendingPathComponent("S")
        try fm.createDirectory(at: series, withIntermediateDirectories: true)
        try fm.zipItem(at: staging, to: series.appendingPathComponent("Chapter 1.cbz"), shouldKeepParent: false)

        let pages = try await source().pages(url: "S/Chapter 1.cbz")

        XCTAssertEqual(pages.map { URL(string: $0.url)?.lastPathComponent }, ["1.jpg", "2.jpg", "10.jpg"])
        XCTAssertTrue(pages.allSatisfy { URL(string: $0.url)?.isFileURL == true })
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(URL(string: pages[2].url))), Data("10.jpg".utf8))
    }

    func testFolderChapterPages() async throws {
        try write("S/Ch 1/b.png")
        try write("S/Ch 1/a.png")
        try write("S/Ch 1/notes.txt")

        let pages = try await source().pages(url: "S/Ch 1")

        XCTAssertEqual(pages.map { URL(string: $0.url)?.lastPathComponent }, ["a.png", "b.png"])
    }

    func testRejectsPathsOutsideTheFolder() async throws {
        try write("S/Ch 1/a.png")
        let local = source()

        do {
            _ = try await local.chapters(url: "..")
            XCTFail("expected an error")
        } catch {}
        do {
            _ = try await local.pages(url: "S/../../x")
            XCTFail("expected an error")
        } catch {}
    }
}
