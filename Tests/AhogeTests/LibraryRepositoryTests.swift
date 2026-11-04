import GRDB
import XCTest
@testable import Ahoge

@MainActor
final class LibraryRepositoryTests: XCTestCase {
    private func repository() throws -> LibraryRepository {
        try LibraryRepository.inMemory()
    }

    private func chapter(_ url: String, _ number: Double) -> SourceChapter {
        SourceChapter(url: url, name: "Ch \(Int(number))", number: number, date: nil, scanlator: nil)
    }

    func testUpsertLibraryAndChapters() throws {
        let repo = try repository()
        let manga = repo.upsert(sourceId: "en.demo", url: "/m/1", title: "One", cover: "https://c/1.jpg")
        XCTAssertFalse(manga.inLibrary)
        repo.setInLibrary(manga, true)
        XCTAssertNotNil(manga.dateAdded)
        XCTAssertTrue(repo.manga(sourceId: "en.demo", url: "/m/1") === manga)

        repo.applyChapters([chapter("/c/3", 3), chapter("/c/2", 2), chapter("/c/1", 1)], to: manga)
        XCTAssertEqual(manga.sortedChapters.map(\.url), ["/c/3", "/c/2", "/c/1"])
        XCTAssertEqual(manga.unreadCount, 3)

        repo.markPreviousRead(try XCTUnwrap(manga.sortedChapters.first { $0.url == "/c/2" }), in: manga)
        XCTAssertEqual(manga.sortedChapters.map(\.read), [false, true, true])

        repo.saveProgress(try XCTUnwrap(manga.sortedChapters.first), page: 4, pageCount: 5)
        XCTAssertEqual(manga.sortedChapters.first?.read, true)
        XCTAssertNotNil(manga.lastReadAt)

        repo.applyChapters([chapter("/c/4", 4), chapter("/c/3", 3), chapter("/c/2", 2)], to: manga)
        XCTAssertEqual(manga.sortedChapters.map(\.url), ["/c/4", "/c/3", "/c/2"])
        XCTAssertEqual(manga.sortedChapters.map(\.read), [false, true, true])
    }

    func testDetailsUpdateKeepsLibraryFlag() throws {
        let repo = try repository()
        let manga = repo.upsert(sourceId: "en.demo", url: "/m/1", title: "One", cover: "")
        repo.setInLibrary(manga, true)
        let details = try JSONDecoder().decode(MangaDetails.self, from: Data(#"{"title":"One Full","cover":"https://c/big.jpg","author":"A","artist":"B","description":"D","genres":["Action"],"status":"ongoing"}"#.utf8))
        let updated = repo.upsert(sourceId: "en.demo", url: "/m/1", details: details)
        XCTAssertTrue(updated === manga)
        XCTAssertTrue(updated.inLibrary)
        XCTAssertEqual(updated.title, "One Full")
        XCTAssertEqual(updated.genres, ["Action"])
    }

    func testReopenLoadsSavedState() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("library-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: file) }
        let repo = try LibraryRepository.open(at: file)
        let saved = repo.upsert(sourceId: "en.demo", url: "/m/1", title: "One", cover: "")
        let details = try JSONDecoder().decode(MangaDetails.self, from: Data(#"{"title":"One","cover":"","author":"A","artist":"B","description":"D","genres":["Action","Drama"],"status":"ongoing"}"#.utf8))
        repo.upsert(sourceId: "en.demo", url: "/m/1", details: details)
        repo.setInLibrary(saved, true)
        repo.applyChapters([chapter("/c/2", 2), chapter("/c/1", 1)], to: saved)
        repo.saveProgress(try XCTUnwrap(saved.sortedChapters.last), page: 2, pageCount: 10)
        repo.upsert(sourceId: "en.demo", url: "/m/2", title: "Two", cover: "")

        let reopened = try LibraryRepository.open(at: file)
        XCTAssertEqual(reopened.library.map(\.url), ["/m/1"])
        let manga = try XCTUnwrap(reopened.library.first)
        XCTAssertEqual(manga.genres, ["Action", "Drama"])
        XCTAssertNotNil(manga.dateAdded)
        XCTAssertNotNil(manga.lastReadAt)
        XCTAssertEqual(manga.sortedChapters.map(\.url), ["/c/2", "/c/1"])
        XCTAssertEqual(manga.sortedChapters.map(\.lastPageRead), [0, 2])
        XCTAssertTrue(manga.sortedChapters.allSatisfy { $0.manga === manga })
        XCTAssertEqual(reopened.manga(sourceId: "en.demo", url: "/m/2")?.title, "Two")
        XCTAssertNil(reopened.manga(sourceId: "en.demo", url: "/m/3"))
    }

    func testUnreadCountFollowsReadChanges() throws {
        let repo = try repository()
        let manga = repo.upsert(sourceId: "en.demo", url: "/m/9", title: "Nine", cover: "")
        repo.applyChapters([chapter("/c/2", 2), chapter("/c/1", 1)], to: manga)
        XCTAssertEqual(manga.unreadCount, 2)
        repo.setRead([try XCTUnwrap(manga.chapters.first)], true)
        XCTAssertEqual(manga.unreadCount, 1)
        repo.saveProgress(try XCTUnwrap(manga.chapters.first { !$0.read }), page: 9, pageCount: 10)
        XCTAssertEqual(manga.unreadCount, 0)
    }

    func testDateFetchSurvivesReopen() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("library-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: file) }
        let repo = try LibraryRepository.open(at: file)
        let manga = repo.upsert(sourceId: "en.demo", url: "/m/1", title: "One", cover: "")
        repo.applyChapters([chapter("/c/1", 1)], to: manga)
        repo.applyChapters([chapter("/c/2", 2), chapter("/c/1", 1)], to: manga)

        let reopened = try LibraryRepository.open(at: file)
        let loaded = try XCTUnwrap(reopened.manga(key: manga.key))
        XCTAssertNotNil(loaded.chapters.first { $0.url == "/c/2" }?.dateFetch)
        XCTAssertNil(loaded.chapters.first { $0.url == "/c/1" }?.dateFetch)
    }

    func testEmptyFetchKeepsChapters() throws {
        let repo = try repository()
        let manga = repo.upsert(sourceId: "en.demo", url: "/m/1", title: "One", cover: "")
        repo.applyChapters([chapter("/c/2", 2), chapter("/c/1", 1)], to: manga)
        repo.setRead([try XCTUnwrap(manga.chapters.first { $0.url == "/c/1" })], true)
        repo.applyChapters([], to: manga)
        XCTAssertEqual(manga.sortedChapters.map(\.url), ["/c/2", "/c/1"])
        XCTAssertEqual(manga.sortedChapters.map(\.read), [false, true])
        XCTAssertEqual(manga.unreadCount, 1)
    }

    func testV3MigrationKeepsExistingRowsWithDefaults() throws {
        let queue = try DatabaseQueue()
        try LibraryRepository.migrator.migrate(queue, upTo: "v2")
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO manga (key, sourceId, url, title, coverUrl, author, artist, summary, genres, status, inLibrary)
                VALUES ('en.demo\n/m/1', 'en.demo', '/m/1', 'One', '', '', '', '', '[]', 'ongoing', 1)
                """)
            try db.execute(sql: """
                INSERT INTO chapter (key, mangaKey, url, name, number, read, lastPageRead, sourceOrder)
                VALUES ('en.demo\n/c/1', 'en.demo\n/m/1', '/c/1', 'Ch 1', 1, 0, 3, 0)
                """)
            try db.execute(sql: "INSERT INTO category (name, sort) VALUES ('Reading', 0)")
            try db.execute(sql: "INSERT INTO history (chapterKey, mangaKey, lastRead) VALUES ('en.demo\n/c/1', 'en.demo\n/m/1', '2026-01-01 00:00:00')")
        }

        let repo = try LibraryRepository(db: queue)

        let manga = try XCTUnwrap(repo.manga(key: "en.demo\n/m/1"))
        XCTAssertEqual(manga.title, "One")
        XCTAssertEqual(manga.notes, "")
        XCTAssertNil(manga.customCover)
        XCTAssertNil(manga.updateInterval)
        XCTAssertNil(manga.nextUpdate)
        XCTAssertEqual(manga.chapterFlags, 0)
        let chapter = try XCTUnwrap(manga.chapters.first)
        XCTAssertEqual(chapter.lastPageRead, 3)
        XCTAssertFalse(chapter.bookmark)
        XCTAssertEqual(repo.categories.map(\.name), ["Reading"])
        XCTAssertEqual(repo.categories.first?.flags, 0)
        XCTAssertNil(repo.categories.first?.sortMode)
        XCTAssertEqual(try queue.read { try Int.fetchOne($0, sql: "SELECT timeRead FROM history") }, 0)
        XCTAssertEqual(try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM download") }, 0)
        XCTAssertEqual(try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM excludedScanlator") }, 0)
    }
}
