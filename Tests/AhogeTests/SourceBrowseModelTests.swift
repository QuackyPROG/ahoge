import XCTest
@testable import Ahoge

@MainActor
final class SourceBrowseModelTests: XCTestCase {
    func testPaginatesAndDeduplicates() async throws {
        let model = SourceBrowseModel(sourceId: "en.demo")
        var calls: [Int] = []
        let fetch: SourceBrowseModel.Fetch = { _, _, page in
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
    }
}
