import XCTest
@testable import Ahoge

@MainActor
final class UpdatesHistoryTests: XCTestCase {
    private func chapter(_ url: String, _ number: Double) -> SourceChapter {
        SourceChapter(url: url, name: "Ch \(Int(number))", number: number, date: nil, scanlator: nil)
    }

    func testUpdatesListOnlyChaptersFoundAfterAdding() throws {
        let repo = try LibraryRepository.inMemory()
        let manga = repo.upsert(sourceId: "en.demo", url: "/m/1", title: "One", cover: "")
        repo.applyChapters([chapter("/c/1", 1)], to: manga)
        repo.setInLibrary(manga, true)
        XCTAssertTrue(repo.updates(since: .distantPast).isEmpty)

        repo.applyChapters([chapter("/c/3", 3), chapter("/c/2", 2), chapter("/c/1", 1)], to: manga)
        XCTAssertEqual(repo.updates(since: .distantPast).map(\.chapter.url), ["/c/3", "/c/2"])
        XCTAssertTrue(repo.updates(since: Date().addingTimeInterval(60)).isEmpty)
    }

    func testCachedFeedFollowsNewChaptersAndLibraryChanges() throws {
        let repo = try LibraryRepository.inMemory()
        let manga = repo.upsert(sourceId: "en.demo", url: "/m/1", title: "One", cover: "")
        repo.applyChapters([chapter("/c/1", 1)], to: manga)
        repo.setInLibrary(manga, true)
        XCTAssertTrue(repo.updates(since: .distantPast).isEmpty) // fills the cache

        repo.applyChapters([chapter("/c/2", 2), chapter("/c/1", 1)], to: manga)
        XCTAssertEqual(repo.updates(since: .distantPast).map(\.chapter.url), ["/c/2"])
        XCTAssertEqual(repo.updates(since: .distantPast).map(\.chapter.url), ["/c/2"]) // from the cache

        repo.setInLibrary(manga, false)
        XCTAssertTrue(repo.updates(since: .distantPast).isEmpty)
    }

    func testUpdatesSkipTitlesOutsideTheLibrary() throws {
        let repo = try LibraryRepository.inMemory()
        let manga = repo.upsert(sourceId: "en.demo", url: "/m/1", title: "One", cover: "")
        repo.applyChapters([chapter("/c/1", 1)], to: manga)
        repo.applyChapters([chapter("/c/2", 2), chapter("/c/1", 1)], to: manga)
        XCTAssertTrue(repo.updates(since: .distantPast).isEmpty)
    }

    func testHistoryKeepsTheLatestChapterPerManga() throws {
        let repo = try LibraryRepository.inMemory()
        let one = repo.upsert(sourceId: "en.demo", url: "/m/1", title: "One", cover: "")
        repo.applyChapters([chapter("/c/2", 2), chapter("/c/1", 1)], to: one)
        let two = repo.upsert(sourceId: "en.demo", url: "/m/2", title: "Two", cover: "")
        repo.applyChapters([chapter("/d/1", 1)], to: two)
        let c1 = try XCTUnwrap(one.chapters.first { $0.url == "/c/1" })
        let c2 = try XCTUnwrap(one.chapters.first { $0.url == "/c/2" })
        let d1 = try XCTUnwrap(two.chapters.first)

        repo.recordHistory(c1, at: Date(timeIntervalSince1970: 100))
        repo.recordHistory(d1, at: Date(timeIntervalSince1970: 200))
        repo.recordHistory(c2, at: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(repo.history().map(\.chapter.url), ["/c/2", "/d/1"])
        XCTAssertEqual(repo.history().first?.lastRead, Date(timeIntervalSince1970: 300))

        repo.removeHistory(chapterKey: c2.key)
        XCTAssertEqual(repo.history().map(\.chapter.url), ["/d/1", "/c/1"])
        repo.removeHistory(mangaKey: one.key)
        XCTAssertEqual(repo.history().map(\.chapter.url), ["/d/1"])
        repo.clearHistory()
        XCTAssertTrue(repo.history().isEmpty)
    }

    func testResumeMovesOnOnceFinished() throws {
        let repo = try LibraryRepository.inMemory()
        let manga = repo.upsert(sourceId: "en.demo", url: "/m/1", title: "One", cover: "")
        repo.applyChapters([chapter("/c/2", 2), chapter("/c/1", 1)], to: manga)
        let c1 = try XCTUnwrap(manga.chapters.first { $0.url == "/c/1" })
        repo.recordHistory(c1)
        XCTAssertEqual(repo.history().first?.resumeChapter?.url, "/c/1")
        repo.setRead([c1], true)
        XCTAssertEqual(repo.history().first?.resumeChapter?.url, "/c/2")
    }

    func testSavingProgressRecordsHistory() throws {
        let repo = try LibraryRepository.inMemory()
        let manga = repo.upsert(sourceId: "en.demo", url: "/m/1", title: "One", cover: "")
        repo.applyChapters([chapter("/c/1", 1)], to: manga)
        repo.saveProgress(try XCTUnwrap(manga.chapters.first), page: 3, pageCount: 10)
        XCTAssertEqual(repo.history().first?.chapter.url, "/c/1")
    }
}

@MainActor
final class ReadingTimeTests: XCTestCase {
    func testReadingTimeAddsUpAndSkipsIncognito() throws {
        let repo = try LibraryRepository.inMemory()
        let suite = "ahoge.test.readingtime.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        repo.preferences = defaults
        let manga = repo.upsert(sourceId: "en.demo", url: "/m/1", title: "One", cover: "")
        repo.applyChapters([SourceChapter(url: "/c/1", name: "Ch 1", number: 1, date: nil, scanlator: nil)], to: manga)
        let chapter = try XCTUnwrap(manga.chapters.first)
        repo.recordHistory(chapter)

        repo.addReadingTime(40, to: chapter)
        repo.addReadingTime(25, to: chapter)
        Pref.incognito.set(true, in: defaults)
        repo.addReadingTime(1000, to: chapter)

        XCTAssertEqual(repo.historyByChapter()[chapter.key]?.timeRead, 65)
    }
}
