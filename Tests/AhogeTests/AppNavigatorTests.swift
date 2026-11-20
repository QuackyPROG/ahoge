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

    func testALinkTappedInAMangaPagesMigrateSearchStacksOnTopOfIt() {
        let navigator = AppNavigator()
        navigator.tab = .library
        navigator.push(.manga(one))
        navigator.push(.migrate(one))
        navigator.push(.sourceSearch("en.demo", query: "One"))
        XCTAssertEqual(navigator.path(for: .library), [.manga(one), .migrate(one), .sourceSearch("en.demo", query: "One")])
    }

    func testMoreMigrateASourceThenATitleStacksTheMigrateSearchOnTop() {
        let navigator = AppNavigator()
        navigator.tab = .more
        navigator.push(.migrateSources)
        navigator.push(.migrateTitles("s"))
        navigator.push(.migrate(one))
        XCTAssertEqual(navigator.path(for: .more), [.migrateSources, .migrateTitles("s"), .migrate(one)])
    }

    func testATitleTappedInUpcomingStacksOnTopOfIt() {
        let navigator = AppNavigator()
        navigator.tab = .updates
        navigator.push(.upcoming)
        navigator.push(.manga(one))
        XCTAssertEqual(navigator.path(for: .updates), [.upcoming, .manga(one)])
    }

    func testMigratingFromAMangaPageReplacesThePageAndTheSearch() {
        XCTAssertEqual([Route].finishingMigration([.manga(one), .migrate(one)], from: one, to: two), [.manga(two)])
    }

    func testMigratingKeepsWhatWasBelowTheOldPage() {
        XCTAssertEqual(
            [Route].finishingMigration([.globalSearch("x"), .manga(one), .migrate(one)], from: one, to: two),
            [.globalSearch("x"), .manga(two)]
        )
    }

    func testMigratingFromMoreMigrateReturnsToTheTitlesList() {
        XCTAssertEqual(
            [Route].finishingMigration([.migrateSources, .migrateTitles("s"), .migrate(one)], from: one, to: two),
            [.migrateSources, .migrateTitles("s")]
        )
    }

    func testMigratingDropsScreensOpenedFromTheMigrateSearch() {
        XCTAssertEqual(
            [Route].finishingMigration([.manga(one), .migrate(one), .sourceSearch("en.demo", query: "One")], from: one, to: two),
            [.manga(two)]
        )
    }

    func testMigratingLeavesAPathWithoutTheMigrateSearchAlone() {
        let path: [Route] = [.manga(one), .globalSearch("x")]
        XCTAssertEqual([Route].finishingMigration(path, from: one, to: two), path)
    }

    func testMigratingMatchesAPageOpenedWithoutTitleOrCover() {
        // A deep link opens a page with an empty title; Migrate pushes the library entry's full ref.
        let bare = MangaRef(sourceId: one.sourceId, url: one.url, title: "", cover: "")
        XCTAssertEqual([Route].finishingMigration([.manga(bare), .migrate(one)], from: one, to: two), [.manga(two)])
    }

    func testFinishMigrationRewritesTheSelectedTabsPath() {
        let navigator = AppNavigator()
        navigator.tab = .library
        navigator.push(.manga(one))
        navigator.push(.migrate(one))
        navigator.finishMigration(from: one, to: two)
        XCTAssertEqual(navigator.path(for: .library), [.manga(two)])
    }

    func testOpeningAMangaSelectsLibraryAndQueuesTheRoute() {
        let navigator = AppNavigator()
        navigator.tab = .more
        navigator.open(.manga(one))
        XCTAssertEqual(navigator.tab, .library)
        XCTAssertEqual(navigator.pendingRoute, .manga(one))
    }
}
