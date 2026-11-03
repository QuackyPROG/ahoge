import XCTest
@testable import Ahoge

@MainActor
final class ClearDatabaseTests: XCTestCase {
    private func add(_ repo: LibraryRepository, source: String, url: String, inLibrary: Bool = false, read: Bool = false) {
        let manga = repo.upsert(sourceId: source, url: url, title: url, cover: "")
        repo.applyChapters([SourceChapter(url: url + "/c1", name: "Ch 1", number: 1, date: nil, scanlator: nil)], to: manga)
        if read { repo.setRead(manga.chapters, true) }
        if inLibrary { repo.setInLibrary(manga, true) }
    }

    func testRemovesOnlyOpenedTitlesOfTheChosenSources() throws {
        let repo = try LibraryRepository.inMemory()
        add(repo, source: "en.a", url: "/saved", inLibrary: true)
        add(repo, source: "en.a", url: "/opened")
        add(repo, source: "en.b", url: "/other-source")

        let removed = repo.clearNonLibrary(sources: ["en.a"], keepRead: false)

        XCTAssertEqual(removed, 1)
        XCTAssertNotNil(repo.manga(sourceId: "en.a", url: "/saved"))
        XCTAssertNil(repo.manga(sourceId: "en.a", url: "/opened"))
        XCTAssertNotNil(repo.manga(sourceId: "en.b", url: "/other-source"))
        XCTAssertEqual(try repo.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM chapter") }, 2)
    }

    func testKeepReadSparesTitlesWithReadChapters() throws {
        let repo = try LibraryRepository.inMemory()
        add(repo, source: "en.a", url: "/read", read: true)
        add(repo, source: "en.a", url: "/unread")

        XCTAssertEqual(repo.nonLibraryCounts(keepRead: true), ["en.a": 1])
        XCTAssertEqual(repo.nonLibraryCounts(keepRead: false), ["en.a": 2])
        XCTAssertEqual(repo.clearNonLibrary(sources: ["en.a"], keepRead: true), 1)
        XCTAssertNotNil(repo.manga(sourceId: "en.a", url: "/read"))
        XCTAssertNil(repo.manga(sourceId: "en.a", url: "/unread"))
    }

    func testTitlesWithDownloadsStay() throws {
        let repo = try LibraryRepository.inMemory()
        add(repo, source: "en.a", url: "/downloaded")
        let manga = try XCTUnwrap(repo.manga(sourceId: "en.a", url: "/downloaded"))
        let chapter = try XCTUnwrap(manga.chapters.first)
        repo.write { db in
            try db.execute(sql: "INSERT INTO download (chapterKey, mangaKey, state, pageCount, bytes, dateAdded) VALUES (?, ?, 2, 3, 100, '2026-01-01 00:00:00')", arguments: [chapter.key, manga.key])
        }

        XCTAssertEqual(repo.clearNonLibrary(sources: ["en.a"], keepRead: false), 0)
        XCTAssertNotNil(repo.manga(sourceId: "en.a", url: "/downloaded"))
    }
}
