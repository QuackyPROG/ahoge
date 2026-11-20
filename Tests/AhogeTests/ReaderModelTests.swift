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
        await model.open(reader.manga.chapter(5), provider: reader.provider, repo: reader.repo)
        model.position = ReaderModel.pageID("/c/5", 2)
        model.positionChanged(repo: reader.repo, provider: reader.provider)
        try await waitUntil { gate.isWaiting }
        await model.open(reader.manga.chapter(4), provider: reader.provider, repo: reader.repo)
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

    func testOpeningAnotherChapterCreditsTheTimeToTheChapterBefore() async throws {
        let reader = try reader(chapters: 2, start: 1)
        let model = reader.model
        let (one, two) = (reader.manga.chapter(1), reader.manga.chapter(2))
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        await model.open(one, provider: reader.provider, repo: reader.repo)
        reader.repo.recordHistory(one)
        model.startClock(now: t0)
        await model.open(two, provider: reader.provider, repo: reader.repo, now: t0.addingTimeInterval(60))
        reader.repo.recordHistory(two)
        model.startClock(now: t0.addingTimeInterval(60))
        model.stopClock(repo: reader.repo, now: t0.addingTimeInterval(90))
        let history = reader.repo.historyByChapter()
        XCTAssertEqual(history[one.key]?.timeRead, 60)
        XCTAssertEqual(history[two.key]?.timeRead, 30)
    }

    func testTallPageBecomesSliceItemsInWebtoonMode() async throws {
        let reader = try reader(chapters: 1, start: 1)
        let model = reader.model
        model.layout = ReaderModel.Layout(sliceTall: true)
        await model.open(reader.manga.chapter(1), provider: reader.provider, repo: reader.repo)
        let page = ReaderModel.pageID("/c/1", 0)
        model.learnSize(CGSize(width: 800, height: 20000), of: page)
        let slices = model.items.filter { item in
            if case .page(_, let index, _) = item.kind { return index == 0 }
            return false
        }
        XCTAssertEqual(slices.map(\.slice), [0, 1, 2, 3, 4])
        XCTAssertEqual(model.itemID(containing: page), slices.first?.id)
    }

    private func pageItems(_ model: ReaderModel, index: Int) -> [ReaderModel.Item] {
        model.items.filter { item in
            if case .page(_, let page, _) = item.kind { return page == index }
            return false
        }
    }

    func testWebtoonPagesAreSlicesFromTheStart() async throws {
        let reader = try reader(chapters: 1, start: 1)
        let model = reader.model
        model.layout = ReaderModel.Layout(sliceTall: true)
        await model.open(reader.manga.chapter(1), provider: reader.provider, repo: reader.repo)
        let pages = model.items.filter { if case .page = $0.kind { return true } else { return false } }
        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(pages.map(\.slice), [0, 0, 0])
        XCTAssertEqual(pages.map(\.id), (0..<3).map { ReaderModel.pageID("/c/1", $0) })
    }

    func testTallPageKeepsItsIDAndSliceZeroWhenSliced() async throws {
        let reader = try reader(chapters: 1, start: 1)
        let model = reader.model
        model.layout = ReaderModel.Layout(sliceTall: true)
        await model.open(reader.manga.chapter(1), provider: reader.provider, repo: reader.repo)
        let page = ReaderModel.pageID("/c/1", 0)
        model.learnSize(CGSize(width: 800, height: 20000), of: page)
        let items = pageItems(model, index: 0)
        XCTAssertEqual(items.first?.id, page)
        XCTAssertEqual(items.map(\.slice), [0, 1, 2, 3, 4])
    }

    func testSliceCountFollowsTheWebtoonWidth() async throws {
        let reader = try reader(chapters: 1, start: 1)
        let model = reader.model
        model.layout = ReaderModel.Layout(sliceTall: true, webtoonWidth: 1179)
        await model.open(reader.manga.chapter(1), provider: reader.provider, repo: reader.repo)
        model.learnSize(CGSize(width: 2048, height: 20000), of: ReaderModel.pageID("/c/1", 0))
        XCTAssertEqual(pageItems(model, index: 0).count, 3)
    }

    func testOnlyThePreviousCurrentAndNextChapterStayLoaded() async throws {
        let reader = try reader(chapters: 5, pageCount: 3, start: 1)
        let model = reader.model
        await model.open(reader.manga.chapter(1), provider: reader.provider, repo: reader.repo)
        for number in 1...3 {
            model.position = ReaderModel.pageID("/c/\(number)", 2)
            model.positionChanged(repo: reader.repo, provider: reader.provider)
            try await waitUntil { !model.isLoadingNext && model.sections.contains { $0.id == "/c/\(number + 1)" } }
            XCTAssertLessThanOrEqual(model.sections.count, 3)
        }
        XCTAssertEqual(model.currentChapter.url, "/c/3")
        XCTAssertEqual(model.sections.map(\.id), ["/c/2", "/c/3", "/c/4"])
        let position = try XCTUnwrap(model.position)
        XCTAssertTrue(model.items.contains { $0.id == position })
    }

    func testOpenAtASavedPageStartsThere() async throws {
        let reader = try reader(chapters: 2, pageCount: 10, start: 1)
        let model = reader.model
        await model.open(reader.manga.chapter(1), page: 7, provider: reader.provider, repo: reader.repo)
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
