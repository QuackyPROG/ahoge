import XCTest
@testable import Ahoge

@MainActor
final class MigrateTests: XCTestCase {
    private func chapter(_ url: String, _ number: Double) -> SourceChapter {
        SourceChapter(url: url, name: "Ch \(number)", number: number, date: nil, scanlator: nil)
    }

    /// An old entry in the library on source "old" and a fetched copy on source "new".
    private func pair(_ repo: LibraryRepository) -> (old: LibraryManga, new: LibraryManga) {
        let old = repo.upsert(sourceId: "old", url: "/m", title: "Title", cover: "")
        repo.applyChapters([chapter("/o/3", 3), chapter("/o/2", 2), chapter("/o/1", 1)], to: old)
        repo.setInLibrary(old, true)
        let new = repo.upsert(sourceId: "new", url: "/n", title: "Title", cover: "")
        repo.applyChapters([chapter("/n/4", 4), chapter("/n/3", 3), chapter("/n/2", 2), chapter("/n/1.5", 1.5), chapter("/n/1", 1)], to: new)
        return (old, new)
    }

    private func reloaded(_ repo: LibraryRepository, key: String) throws -> LibraryManga {
        let fresh = try LibraryRepository(db: repo.db)
        return try XCTUnwrap(fresh.manga(key: key))
    }

    func testReadStateCarriesOverByChapterNumber() throws {
        let repo = try LibraryRepository.inMemory()
        let (old, new) = pair(repo)
        repo.setRead(old.chapters.filter { $0.number <= 2 }, true)

        repo.migrate(old, to: new, options: MigrateOptions())

        let saved = try reloaded(repo, key: new.key)
        let read = saved.chapters.filter(\.read).map(\.url).sorted()
        // 1.5 has no match but sits below the highest read number (2).
        XCTAssertEqual(read, ["/n/1", "/n/1.5", "/n/2"])
        XCTAssertEqual(saved.unreadCount, 2)
    }

    func testBookmarksCarryOver() throws {
        let repo = try LibraryRepository.inMemory()
        let (old, new) = pair(repo)
        repo.setBookmark(old.chapters.filter { $0.url == "/o/3" }, true)

        repo.migrate(old, to: new, options: MigrateOptions())

        let saved = try reloaded(repo, key: new.key)
        XCTAssertEqual(saved.chapters.filter(\.bookmark).map(\.url), ["/n/3"])
    }

    func testCategoriesNotesCoverAndScanlatorsCarryOver() throws {
        let repo = try LibraryRepository.inMemory()
        let (old, new) = pair(repo)
        let shelf = try XCTUnwrap(repo.createCategory(named: "Reading"))
        repo.setCategories([shelf.id], for: old)
        repo.setNotes("Volume 2 is missing", for: old)
        repo.setExcludedScanlators(["Slow Scans"], for: old)
        old.customCover = "abc.jpg"

        repo.migrate(old, to: new, options: MigrateOptions())

        let fresh = try LibraryRepository(db: repo.db)
        let saved = try XCTUnwrap(fresh.manga(key: new.key))
        XCTAssertEqual(fresh.categoryIds(of: saved), [shelf.id])
        XCTAssertEqual(saved.notes, "Volume 2 is missing")
        XCTAssertEqual(saved.customCover, "abc.jpg")
        XCTAssertEqual(fresh.excludedScanlators(mangaKey: new.key), ["Slow Scans"])
    }

    func testMigrateRemovesTheOldEntryFromTheLibrary() throws {
        let repo = try LibraryRepository.inMemory()
        let (old, new) = pair(repo)
        let shelf = try XCTUnwrap(repo.createCategory(named: "Reading"))
        repo.setCategories([shelf.id], for: old)

        repo.migrate(old, to: new, options: MigrateOptions())

        let fresh = try LibraryRepository(db: repo.db)
        XCTAssertEqual(fresh.library.map(\.key), [new.key])
        let gone = try XCTUnwrap(fresh.manga(key: old.key))
        XCTAssertFalse(gone.inLibrary)
        XCTAssertEqual(fresh.categoryIds(of: gone), [])
    }

    func testCopyKeepsTheOldEntry() throws {
        let repo = try LibraryRepository.inMemory()
        let (old, new) = pair(repo)
        var options = MigrateOptions()
        options.removeOld = false

        repo.migrate(old, to: new, options: options)

        let fresh = try LibraryRepository(db: repo.db)
        XCTAssertEqual(Set(fresh.library.map(\.key)), [old.key, new.key])
    }

    func testOptionsLeaveOutWhatIsSwitchedOff() throws {
        let repo = try LibraryRepository.inMemory()
        let (old, new) = pair(repo)
        let shelf = try XCTUnwrap(repo.createCategory(named: "Reading"))
        repo.setCategories([shelf.id], for: old)
        repo.setNotes("note", for: old)
        repo.setRead(old.chapters, true)
        let options = MigrateOptions(chapters: false, categories: false, notes: false, customCover: false, deleteDownloads: false, removeOld: true)

        repo.migrate(old, to: new, options: options)

        let fresh = try LibraryRepository(db: repo.db)
        let saved = try XCTUnwrap(fresh.manga(key: new.key))
        XCTAssertTrue(saved.inLibrary)
        XCTAssertEqual(saved.chapters.filter(\.read).count, 0)
        XCTAssertEqual(saved.notes, "")
        XCTAssertEqual(fresh.categoryIds(of: saved), [])
    }
}
