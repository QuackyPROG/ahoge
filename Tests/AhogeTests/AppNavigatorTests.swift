import XCTest
@testable import Ahoge

@MainActor
final class AppNavigatorTests: XCTestCase {
    private let one = MangaRef(sourceId: "en.demo", url: "/series/one", title: "One", cover: "")
    private let two = MangaRef(sourceId: "en.demo", url: "/series/two", title: "Two", cover: "")

    func testPushAppendsToTheSelectedTabOnly() {
        let navigator = AppNavigator()
        navigator.tab = .browse
        navigator.push(.manga(one))
        navigator.push(.manga(two))
        XCTAssertEqual(navigator.path(for: .browse), [.manga(one), .manga(two)])
        for tab in AppTab.allCases where tab != .browse {
            XCTAssertEqual(navigator.path(for: tab), [], "\(tab)")
        }
    }

    func testSwitchingTabThenPushingLeavesTheOtherTabsPathAlone() {
        let navigator = AppNavigator()
        navigator.tab = .history
        navigator.push(.manga(one))
        navigator.tab = .updates
        navigator.push(.manga(two))
        XCTAssertEqual(navigator.path(for: .history), [.manga(one)])
        XCTAssertEqual(navigator.path(for: .updates), [.manga(two)])
    }

    func testAResultTappedInGlobalSearchStacksOnTopOfIt() {
        let navigator = AppNavigator()
        navigator.tab = .browse
        navigator.push(.globalSearch("q"))
        navigator.push(.manga(one))
        XCTAssertEqual(navigator.path(for: .browse), [.globalSearch("q"), .manga(one)])
    }

    func testOpeningAMangaSelectsLibraryAndQueuesTheRoute() {
        let navigator = AppNavigator()
        navigator.tab = .more
        navigator.open(.manga(one))
        XCTAssertEqual(navigator.tab, .library)
        XCTAssertEqual(navigator.pendingRoute, .manga(one))
    }
    func testReadOpensTheReaderAndCloseReaderClearsIt() {
        let navigator = AppNavigator()
        let manga = LibraryManga(sourceId: "en.demo", url: "/series/one", title: "One", coverUrl: "")
        let chapter = ChapterRecord(manga: manga, state: ChapterState(url: "/c/1", name: "Ch 1", number: 1, read: false, lastPageRead: 0, sourceOrder: 0))
        navigator.read(chapter, in: manga)
        XCTAssertTrue(navigator.reader?.manga === manga)
        XCTAssertTrue(navigator.reader?.chapter === chapter)
        XCTAssertEqual(navigator.reader?.sourceId, "en.demo")
        navigator.closeReader()
        XCTAssertNil(navigator.reader)
    }
    func testTheReaderHoldsItsMangaWhenNothingElseDoes() {
        let navigator = AppNavigator()
        weak var held: LibraryManga?
        do {
            let manga = LibraryManga(sourceId: "en.demo", url: "/series/one", title: "One", coverUrl: "")
            let chapter = ChapterRecord(manga: manga, state: ChapterState(url: "/c/1", name: "Ch 1", number: 1, read: false, lastPageRead: 0, sourceOrder: 0))
            held = manga
            navigator.read(chapter, in: manga)
        }
        XCTAssertNotNil(held)
        XCTAssertEqual(navigator.reader?.manga.title, "One")
    }
    // MARK: Restore on a cold launch
    private func suite() -> UserDefaults {
        UserDefaults(suiteName: "app-navigator-tests-\(UUID().uuidString)")!
    }
    /// Leaves Browse on a source, then a title, with chapter 2 open at page 7.
    private func leaveState(defaults: UserDefaults, repo: LibraryRepository, manga: LibraryManga) {
        let navigator = AppNavigator()
        navigator.restore(from: defaults, repo: repo)
        navigator.tab = .browse
        navigator.push(.source("s"))
        navigator.push(.manga(manga.ref))
        navigator.read(manga.chapter(2), in: manga)
        navigator.readerMoved(to: manga.chapter(2), page: 7)
    }
    func testAColdLaunchRestoresTheTabTheTopTitleAndTheReaderPage() throws {
        let defaults = suite()
        let repo = try LibraryRepository.inMemory()
        repo.preferences = defaults
        let manga = SourceFixture.manga(in: repo, chapters: 3)
        leaveState(defaults: defaults, repo: repo, manga: manga)
        let launched = AppNavigator()
        launched.restore(from: defaults, repo: repo)
        XCTAssertEqual(launched.tab, .browse)
        XCTAssertEqual(launched.path(for: .browse), [.manga(manga.ref)])
        XCTAssertEqual(launched.reader?.chapter.key, manga.chapter(2).key)
        XCTAssertEqual(launched.reader?.manga.key, manga.key)
        XCTAssertEqual(launched.reader?.page, 7)
    }
    func testASavedTitleThatIsGoneRestoresTheTabOnly() throws {
        let defaults = suite()
        let repo = try LibraryRepository.inMemory()
        repo.preferences = defaults
        leaveState(defaults: defaults, repo: repo, manga: SourceFixture.manga(in: repo, chapters: 3))
        let empty = try LibraryRepository.inMemory()
        empty.preferences = defaults
        let launched = AppNavigator()
        launched.restore(from: defaults, repo: empty)
        XCTAssertEqual(launched.tab, .browse)
        XCTAssertEqual(launched.path(for: .browse), [])
        XCTAssertNil(launched.reader)
    }
    func testGlobalIncognitoSavesTheTabOnly() throws {
        let defaults = suite()
        Pref.incognito.set(true, in: defaults)
        try assertOnlyTheTabIsSaved(defaults: defaults)
    }
    func testAnIncognitoSourceSavesTheTabOnly() throws {
        let defaults = suite()
        Pref.incognitoSources.set([SourceFixture.sourceId], in: defaults)
        try assertOnlyTheTabIsSaved(defaults: defaults)
    }
    private func assertOnlyTheTabIsSaved(defaults: UserDefaults, file: StaticString = #filePath, line: UInt = #line) throws {
        let repo = try LibraryRepository.inMemory()
        repo.preferences = defaults
        leaveState(defaults: defaults, repo: repo, manga: SourceFixture.manga(in: repo, chapters: 3))
        let launched = AppNavigator()
        launched.restore(from: defaults, repo: repo)
        XCTAssertEqual(launched.tab, .browse, file: file, line: line)
        XCTAssertEqual(launched.path(for: .browse), [], file: file, line: line)
        XCTAssertNil(launched.reader, file: file, line: line)
    }
}
