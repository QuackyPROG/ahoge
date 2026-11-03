import GRDB
import XCTest
@testable import Ahoge

@MainActor
final class ReaderRepositoryTests: XCTestCase {
    private func chapters(_ repo: LibraryRepository) -> LibraryManga {
        let manga = repo.upsert(sourceId: "en.demo", url: "/m", title: "M", cover: "")
        repo.setInLibrary(manga, true)
        repo.applyChapters([
            SourceChapter(url: "/c/2", name: "Ch 2", number: 2, date: nil, scanlator: nil),
            SourceChapter(url: "/c/1", name: "Ch 1", number: 1, date: nil, scanlator: nil),
        ], to: manga)
        return manga
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let name = "ReaderRepositoryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testBookmarkSurvivesReopen() throws {
        let queue = try DatabaseQueue()
        let repo = try LibraryRepository(db: queue)
        let manga = chapters(repo)
        repo.setBookmark(manga.chapters.filter { $0.url == "/c/1" }, true)

        let reopened = try LibraryRepository(db: queue)
        let saved = try XCTUnwrap(reopened.library.first)
        XCTAssertEqual(saved.sortedChapters.map(\.bookmark), [false, true])
        reopened.setBookmark(saved.chapters, false)
        XCTAssertEqual(try LibraryRepository(db: queue).library.first?.chapters.map(\.bookmark), [false, false])
    }

    func testExcludedScanlatorsAreReadPerManga() throws {
        let repo = try LibraryRepository.inMemory()
        let manga = chapters(repo)
        let other = repo.upsert(sourceId: "en.demo", url: "/other", title: "O", cover: "")
        repo.write { db in
            try db.execute(sql: "INSERT INTO excludedScanlator (mangaKey, scanlator) VALUES (?, 'A'), (?, 'B'), (?, 'C')", arguments: [manga.key, manga.key, other.key])
        }
        XCTAssertEqual(repo.excludedScanlators(mangaKey: manga.key), ["A", "B"])
        XCTAssertEqual(repo.excludedScanlators(mangaKey: "nothing"), [])
    }

    func testIncognitoSourceSavesNoProgressOrHistory() throws {
        let repo = try LibraryRepository.inMemory()
        repo.preferences = try isolatedDefaults()
        let manga = chapters(repo)
        let first = try XCTUnwrap(manga.chapters.first { $0.url == "/c/1" })
        Pref.incognitoSources.set(["en.demo"], in: repo.preferences)

        repo.saveProgress(first, page: 9, pageCount: 10)
        repo.recordHistory(first)
        XCTAssertEqual(first.lastPageRead, 0)
        XCTAssertFalse(first.read)
        XCTAssertNil(manga.lastReadAt)
        XCTAssertTrue(repo.history().isEmpty)

        Pref.incognitoSources.set([], in: repo.preferences)
        repo.saveProgress(first, page: 3, pageCount: 10)
        XCTAssertEqual(first.lastPageRead, 3)
        XCTAssertEqual(repo.history().count, 1)
    }

    func testGlobalIncognitoCoversEverySource() throws {
        let repo = try LibraryRepository.inMemory()
        repo.preferences = try isolatedDefaults()
        let manga = chapters(repo)
        Pref.incognito.set(true, in: repo.preferences)
        repo.saveProgress(try XCTUnwrap(manga.chapters.first), page: 5, pageCount: 10)
        XCTAssertTrue(repo.history().isEmpty)
        XCTAssertEqual(manga.chapters.map(\.lastPageRead), [0, 0])
    }
}
