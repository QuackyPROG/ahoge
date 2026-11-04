import XCTest
@testable import Ahoge

final class DeepLinkTests: XCTestCase {
    private let sources = [
        InstalledSource(id: "en.demo", repoURL: "https://r/index.json", name: "Demo", lang: "en", version: "1.0.0", nsfw: false, baseUrl: "https://demo.example", iconURL: nil, sha256: "x"),
        InstalledSource(id: "en.other", repoURL: "https://r/index.json", name: "Other", lang: "en", version: "1.0.0", nsfw: false, baseUrl: "https://www.other.example", iconURL: nil, sha256: "y"),
    ]

    private func resolve(_ text: String) -> DeepLink? {
        DeepLinkResolver.resolve(URL(string: text)!, sources: sources)
    }

    func testMangaLinkNamesSourceAndPath() {
        XCTAssertEqual(resolve("ahoge://manga?source=en.demo&url=/series/one"), .manga(sourceId: "en.demo", path: "/series/one"))
        XCTAssertEqual(resolve("ahoge://manga?source=local&url=My%20Series"), .manga(sourceId: "local", path: "My Series"))
    }

    func testMangaLinkWithFullWebAddressKeepsOnlyThePath() {
        XCTAssertEqual(resolve("ahoge://manga?source=en.demo&url=https%3A%2F%2Fdemo.example%2Fseries%2Fone"), .manga(sourceId: "en.demo", path: "/series/one"))
    }

    func testMangaLinkOfUnknownSourceOrMissingPartsIsRejected() {
        XCTAssertNil(resolve("ahoge://manga?source=en.gone&url=/x"))
        XCTAssertNil(resolve("ahoge://manga?source=en.demo"))
        XCTAssertNil(resolve("ahoge://manga?url=/x"))
    }

    func testSearchLink() {
        XCTAssertEqual(resolve("ahoge://search?q=one%20piece"), .search("one piece"))
        XCTAssertNil(resolve("ahoge://search?q=%20"))
    }

    func testAddRepoLinkNeedsAWebURL() {
        XCTAssertEqual(resolve("ahoge://add-repo?url=https%3A%2F%2Fexample.com%2Findex.json"), .addRepo(URL(string: "https://example.com/index.json")!))
        XCTAssertNil(resolve("ahoge://add-repo?url=file%3A%2F%2F%2Fetc%2Fpasswd"))
        XCTAssertNil(resolve("ahoge://add-repo"))
    }

    func testWebLinkMatchesASourceByHost() {
        XCTAssertEqual(resolve("https://demo.example/series/one?x=1"), .manga(sourceId: "en.demo", path: "/series/one?x=1"))
        XCTAssertEqual(resolve("https://other.example/a/b"), .manga(sourceId: "en.other", path: "/a/b"))
        XCTAssertEqual(resolve("https://www.demo.example/a"), .manga(sourceId: "en.demo", path: "/a"))
    }

    func testWebLinkOfOtherSitesOrWithoutAPathIsRejected() {
        XCTAssertNil(resolve("https://unknown.example/a"))
        XCTAssertNil(resolve("https://demo.example/"))
        XCTAssertNil(resolve("ftp://demo.example/a"))
        XCTAssertNil(resolve("ahoge://nothing"))
    }
}
