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

    func testOpeningAMangaSelectsLibraryAndQueuesTheRoute() {
        let navigator = AppNavigator()
        navigator.tab = .more
        navigator.open(.manga(one))
        XCTAssertEqual(navigator.tab, .library)
        XCTAssertEqual(navigator.pendingRoute, .manga(one))
    }
}
