import XCTest
@testable import Ahoge

@MainActor
final class SourceBrowseModelTests: XCTestCase {
    private let filters: [SourceFilter] = [
        .checkbox(key: "done", name: "Completed", defaultValue: false),
        .group(key: "genres", name: "Genres", filters: [.tristate(key: "action", name: "Action")]),
    ]

    func testPaginatesAndDeduplicates() async throws {
        let model = SourceBrowseModel(sourceId: "en.demo")
        var calls: [Int] = []
        let fetch: SourceBrowseModel.Fetch = { _, _, page, _ in
            calls.append(page)
            let items = page == 1 ? ["/a", "/b"] : ["/b", "/c"]
            return MangaListPage(manga: items.map { MangaStub(url: $0, title: $0, cover: "") }, hasNextPage: page < 2)
        }
        await model.reload(fetch)
        await model.loadMore(fetch)
        await model.loadMore(fetch)
        XCTAssertEqual(calls, [1, 2])
        XCTAssertEqual(model.items.map(\.url), ["/a", "/b", "/c"])
        XCTAssertNil(model.error)
        XCTAssertFalse(model.foundNothing)
    }

    func testApplyingFiltersSwitchesToFilteredFeed() async throws {
        let model = SourceBrowseModel(sourceId: "en.demo")
        await model.loadFilters { self.filters }
        var seen: [(SourceBrowseModel.Feed, FilterState)] = []
        let fetch: SourceBrowseModel.Fetch = { feed, _, _, state in
            seen.append((feed, state))
            return MangaListPage(manga: [], hasNextPage: false)
        }
        var state = model.filters
        state.values["done"] = .bool(true)
        await model.apply(state, fetch)
        XCTAssertEqual(model.feed, .filtered)
        XCTAssertEqual(seen.last?.0, .filtered)
        XCTAssertEqual(seen.last?.1.values["done"], .bool(true))
        XCTAssertEqual(model.filters.activeCount, 1)
        XCTAssertTrue(model.foundNothing)

        await model.select(.latest, fetch)
        XCTAssertEqual(seen.last?.0, .latest)
        XCTAssertEqual(model.filters.activeCount, 1, "filters are kept for the next filtered browse")
    }

    func testGenreUsesMatchingFilterElseSearch() async {
        let model = SourceBrowseModel(sourceId: "en.demo")
        await model.loadFilters { self.filters }
        model.applyGenre("action")
        XCTAssertEqual(model.feed, .filtered)
        XCTAssertEqual(model.filters.activeCount, 1)
        XCTAssertEqual(model.query, "")

        let other = SourceBrowseModel(sourceId: "en.demo")
        await other.loadFilters { [] }
        other.applyGenre("Romance")
        XCTAssertEqual(other.feed, .popular)
        XCTAssertEqual(other.query, "Romance")
    }

    func testFailingFilterListLeavesNoFilters() async {
        let model = SourceBrowseModel(sourceId: "en.demo")
        await model.loadFilters { throw SourceError.script("boom") }
        XCTAssertTrue(model.filters.isEmpty)
    }
}
