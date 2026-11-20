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
}
