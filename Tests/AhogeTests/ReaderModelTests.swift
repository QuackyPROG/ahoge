import XCTest
@testable import Ahoge

@MainActor
final class ReaderModelTests: XCTestCase {
    func testNextAndPreviousChapterFollowSourceOrder() throws {
        let repo = try LibraryRepository.inMemory()
        let manga = repo.upsert(sourceId: "s", url: "/m", title: "M", cover: "")
        repo.applyChapters((1...3).reversed().map { SourceChapter(url: "/c/\($0)", name: "Ch \($0)", number: Double($0), date: nil, scanlator: nil) }, to: manga)
        let middle = try XCTUnwrap(manga.chapters.first { $0.url == "/c/2" })
        let model = ReaderModel(sourceId: "s", manga: manga, start: middle, rules: SkipRules(), display: ChapterDisplay())
        XCTAssertEqual(model.chapter(after: middle)?.url, "/c/3")
        XCTAssertEqual(model.chapter(before: middle)?.url, "/c/1")
        XCTAssertNil(model.chapter(after: try XCTUnwrap(manga.chapters.first { $0.url == "/c/3" })))
    }
    func testOpenAtASavedPageStartsThere() async throws {
        let repo = try LibraryRepository.inMemory()
        let manga = SourceFixture.manga(in: repo, chapters: 2)
        let sources = SourceManager(extensions: try SourceFixture.extensions(pageCount: 10))
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let downloads = DownloadManager(
            repo: repo, sources: sources, transport: StubTransport.text("page"),
            root: base.appendingPathComponent("d"), cache: base.appendingPathComponent("c"),
            defaults: UserDefaults(suiteName: "reader-model-tests-\(UUID().uuidString)")!, retryDelay: .zero
        )
        let chapter = manga.chapter(1)
        let model = ReaderModel(sourceId: SourceFixture.sourceId, manga: manga, start: chapter, rules: SkipRules(), display: ChapterDisplay())
        await model.open(chapter, page: 7, provider: PageProvider(sources: sources, downloads: downloads))
        XCTAssertNil(model.error)
        XCTAssertEqual(model.currentPage, 7)
    }
}

final class ReadingModeTests: XCTestCase {
    func testPerMangaModeFallsBackToTheDefault() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: "reader.mode.default")
        defer { defaults.set(saved, forKey: "reader.mode.default") }
        let key = "test\n" + UUID().uuidString
        defer { defaults.removeObject(forKey: "reader.mode\n" + key) }

        ReadingMode.preferred = .rightToLeft
        XCTAssertEqual(ReadingMode.load(for: key), .rightToLeft)
        ReadingMode.webtoon.save(for: key)
        XCTAssertEqual(ReadingMode.load(for: key), .webtoon)
        ReadingMode.preferred = .vertical
        XCTAssertEqual(ReadingMode.load(for: key), .webtoon)
    }
}
