import XCTest
@testable import Ahoge

@MainActor
final class GlobalSearchTests: XCTestCase {
    private struct Boom: LocalizedError {
        var errorDescription: String? { "Source is down" }
    }

    private func source(_ id: String, lang: String = "en", nsfw: Bool = false) -> InstalledSource {
        InstalledSource(id: id, repoURL: "https://repo/index.json", name: id.uppercased(), lang: lang, version: "1.0.0", nsfw: nsfw, baseUrl: "https://\(id).example", iconURL: nil, sha256: "x")
    }

    private func page(_ urls: [String]) -> MangaListPage {
        MangaListPage(manga: urls.map { MangaStub(url: $0, title: $0, cover: "") }, hasNextPage: false)
    }

    func testResultsArrivePerSource() async {
        let search = GlobalSearch { id, query in
            self.page(["/\(id)/\(query)"])
        }
        search.run("naruto", sources: [source("a"), source("b")])
        XCTAssertEqual(search.results.map(\.state), [.loading, .loading])
        await search.finished()
        XCTAssertEqual(search.results.map(\.id), ["a", "b"])
        XCTAssertEqual(search.results.map(\.state), [
            .done([MangaStub(url: "/a/naruto", title: "/a/naruto", cover: "")]),
            .done([MangaStub(url: "/b/naruto", title: "/b/naruto", cover: "")]),
        ])
    }

    func testOneFailingSourceDoesNotStopTheOthers() async {
        let search = GlobalSearch { id, _ in
            if id == "b" { throw Boom() }
            return self.page(["/\(id)"])
        }
        search.run("x", sources: [source("a"), source("b"), source("c")], maxConcurrent: 1)
        await search.finished()
        XCTAssertEqual(search.results.map(\.state), [
            .done([MangaStub(url: "/a", title: "/a", cover: "")]),
            .failed("Source is down"),
            .done([MangaStub(url: "/c", title: "/c", cover: "")]),
        ])
        XCTAssertEqual(search.results.map(\.hasResults), [true, false, true])
    }

    func testNoMoreThanMaxConcurrentRunAtOnce() async {
        var running = 0
        var peak = 0
        var calls: [String] = []
        let search = GlobalSearch { id, _ in
            calls.append(id)
            running += 1
            peak = max(peak, running)
            for _ in 0..<5 { await Task.yield() }
            running -= 1
            return self.page([])
        }
        search.run("x", sources: ["a", "b", "c", "d", "e", "f"].map { source($0) }, maxConcurrent: 2)
        await search.finished()
        XCTAssertEqual(peak, 2)
        XCTAssertEqual(calls.sorted(), ["a", "b", "c", "d", "e", "f"])
    }

    func testCancelStopsPendingSources() async {
        var calls: [String] = []
        let search = GlobalSearch { id, _ in
            calls.append(id)
            try await Task.sleep(for: .seconds(30))
            return self.page(["/\(id)"])
        }
        search.run("x", sources: [source("a"), source("b"), source("c")], maxConcurrent: 1)
        for _ in 0..<100 where calls.isEmpty { await Task.yield() }
        search.cancel()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(calls, ["a"])
        XCTAssertEqual(search.results.map(\.state), [.loading, .loading, .loading])
    }

    func testAnEmptyQuerySearchesNothing() async {
        var calls = 0
        let search = GlobalSearch { _, _ in
            calls += 1
            return self.page([])
        }
        search.run("   ", sources: [source("a")])
        await search.finished()
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(search.results.isEmpty)
    }

    // MARK: Which sources

    func testPinnedOnlyKeepsPinnedSourcesInPinnedOrder() {
        let installed = [source("a"), source("b"), source("c")]
        let picked = GlobalSearch.eligible(installed, visibility: SourceVisibility(), pinned: ["c", "a"], pinnedOnly: true)
        XCTAssertEqual(picked.map(\.id), ["c", "a"])
    }

    func testPinnedSourcesComeFirstThenByName() {
        let installed = [source("c"), source("b"), source("a")]
        let picked = GlobalSearch.eligible(installed, visibility: SourceVisibility(), pinned: ["b"], pinnedOnly: false)
        XCTAssertEqual(picked.map(\.id), ["b", "a", "c"])
    }

    func testDisabledHiddenAndExcludedSourcesAreLeftOut() {
        let installed = [source("a"), source("b", lang: "fr"), source("c", nsfw: true), source("d"), source("e")]
        let visibility = SourceVisibility(disabledSources: ["d"], disabledLanguages: ["fr"], content: .safe)
        let picked = GlobalSearch.eligible(installed, visibility: visibility, pinned: [], pinnedOnly: false, excluding: "e")
        XCTAssertEqual(picked.map(\.id), ["a"])
    }

    func testAdultOnlyKeepsTheFlaggedSources() {
        let installed = [source("a"), source("b", nsfw: true)]
        let picked = GlobalSearch.eligible(installed, visibility: SourceVisibility(content: .adult), pinned: [], pinnedOnly: false)
        XCTAssertEqual(picked.map(\.id), ["b"])
    }
}
