import XCTest
@testable import Ahoge

@MainActor
final class SourceManagerTests: XCTestCase {
    func testCachesUntilScriptChangesAndReportsMissing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let script = "var source = { popular: async function () { return { manga: [], hasNextPage: false }; } };"
        let index = """
        {"schema":1,"name":"R","sources":[{"id":"en.demo","name":"Demo","lang":"en","version":"1.0.0","runtime":1,"nsfw":false,
        "baseUrl":"https://demo.test","icon":null,"script":"dist/en.demo.js","sha256":"\(Data(script.utf8).sha256Hex)","health":{"status":"ok","checkedAt":null}}]}
        """
        let stub = StubTransport { request in
            request.url?.lastPathComponent == "index.json" ? (200, [:], Data(index.utf8), nil) : (200, [:], Data(script.utf8), nil)
        }
        let store = ExtensionStore(directory: directory, client: RepoClient(transport: stub))
        try await store.addRepo("https://r.test/index.json")
        try await store.install(try XCTUnwrap(store.rows().first?.source), from: "https://r.test/index.json")

        let manager = SourceManager(extensions: store)
        let first = try manager.source("en.demo")
        XCTAssertTrue(try manager.source("en.demo") === first)
        let page = try await first.popular(page: 1)
        XCTAssertTrue(page.manga.isEmpty)
        XCTAssertThrowsError(try manager.source("en.missing")) { error in
            XCTAssertEqual(error as? SourceError, .notInstalled("en.missing"))
        }
    }
}
