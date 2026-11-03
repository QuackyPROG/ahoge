import XCTest
@testable import Ahoge

@MainActor
final class PageProviderTests: XCTestCase {
    func testDownloadedPagesAreLocalOthersRemoteEvenWithoutTheSource() async throws {
        let repo = try LibraryRepository.inMemory()
        let manga = SourceFixture.manga(in: repo, chapters: 2)
        let extensions = try SourceFixture.extensions(pageCount: 2)
        let sources = SourceManager(extensions: extensions)
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = UserDefaults(suiteName: "page-provider-tests-\(UUID().uuidString)")!
        Pref.downloadOnlyOnWiFi.set(false, in: defaults)
        let downloads = DownloadManager(
            repo: repo, sources: sources, transport: StubTransport.text("page"),
            root: base.appendingPathComponent("d"), cache: base.appendingPathComponent("c"), defaults: defaults, retryDelay: .zero
        )
        downloads.enqueue([manga.chapter(1)])
        await downloads.waitUntilIdle()
        let provider = PageProvider(sources: sources, downloads: downloads)

        let local = try await provider.pages(for: manga.chapter(1))
        XCTAssertEqual(local.map { page -> String in
            if case .local(let url) = page { return url.lastPathComponent }
            return "remote"
        }, ["001.jpg", "002.jpg"])

        let remote = try await provider.pages(for: manga.chapter(2))
        XCTAssertEqual(remote, [
            .remote(SourcePage(url: "https://img.test/c/2/1.jpg", headers: ["Referer": "https://img.test/"])),
            .remote(SourcePage(url: "https://img.test/c/2/2.jpg", headers: ["Referer": "https://img.test/"])),
        ])

        extensions.uninstall(SourceFixture.sourceId)
        let offline = try await provider.pages(for: manga.chapter(1))
        XCTAssertEqual(offline.count, 2)
        do {
            _ = try await provider.pages(for: manga.chapter(2))
            XCTFail("a chapter that is not downloaded needs its source")
        } catch {
            XCTAssertEqual(error as? SourceError, .notInstalled(SourceFixture.sourceId))
        }
    }
}
