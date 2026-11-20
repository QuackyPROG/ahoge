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

    /// Holds a chapter's page lookup until the test opens it.
    private final class Gate {
        private var continuation: CheckedContinuation<Void, Error>?
        var isWaiting: Bool { continuation != nil }

        func wait() async throws {
            try await withCheckedThrowingContinuation { continuation = $0 }
        }

        func open(throwing error: Error? = nil) {
            if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
            continuation = nil
        }
    }

    private struct Reader {
        let repo: LibraryRepository
        let manga: LibraryManga
        let model: ReaderModel
        let provider: PageProvider
    }

    /// A reader of `chapters` chapters of `pageCount` pages; `gate` (if any) holds `gatedChapter`'s lookup.
    private func reader(chapters: Int, pageCount: Int = 3, start: Int, gate: Gate? = nil, gatedChapter: String = "") throws -> Reader {
        let repo = try LibraryRepository.inMemory()
        let manga = SourceFixture.manga(in: repo, chapters: chapters)
        let sources = SourceManager(extensions: try SourceFixture.extensions(pageCount: pageCount))
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let downloads = DownloadManager(
            repo: repo, sources: sources, transport: StubTransport.text("page"),
            root: base.appendingPathComponent("d"), cache: base.appendingPathComponent("c"),
            defaults: UserDefaults(suiteName: "reader-model-tests-\(UUID().uuidString)")!, retryDelay: .zero
        )
        let provider = PageProvider(sources: sources, downloads: downloads) { chapter in
            if chapter.url == gatedChapter { try await gate?.wait() }
            return try await sources.source(chapter.sourceId).pages(url: chapter.url)
        }
        let model = ReaderModel(sourceId: SourceFixture.sourceId, manga: manga, start: manga.chapter(start), rules: SkipRules(), display: ChapterDisplay())
        return Reader(repo: repo, manga: manga, model: model, provider: provider)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("timed out")
    }

    private func staleNextIsDropped(throwing error: Error?) async throws {
        let gate = Gate()
        let reader = try reader(chapters: 6, start: 5, gate: gate, gatedChapter: "/c/6")
        let model = reader.model
        await model.open(reader.manga.chapter(5), provider: reader.provider)
        model.position = ReaderModel.pageID("/c/5", 2)
        model.positionChanged(repo: reader.repo, provider: reader.provider)
        try await waitUntil { gate.isWaiting }
        await model.open(reader.manga.chapter(4), provider: reader.provider)
        gate.open(throwing: error)
        try await waitUntil { !model.isLoadingNext }
        XCTAssertEqual(model.sections.map(\.id), ["/c/4"])
        XCTAssertNil(model.error)
    }

    func testNextChapterLoadedBeforeAJumpIsDropped() async throws {
        try await staleNextIsDropped(throwing: nil)
    }

    func testNextChapterErrorBeforeAJumpIsDropped() async throws {
        try await staleNextIsDropped(throwing: URLError(.timedOut))
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
