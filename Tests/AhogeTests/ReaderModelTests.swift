import SwiftData
import XCTest
@testable import Ahoge

@MainActor
final class ReaderModelTests: XCTestCase {
    /// The container must outlive the repository; a released container crashes its context.
    private var container: ModelContainer!

    func testNextAndPreviousChapterFollowSourceOrder() throws {
        container = try ModelContainer(for: LibraryManga.self, ChapterRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let repo = LibraryRepository(context: container.mainContext)
        let manga = repo.upsert(sourceId: "s", url: "/m", title: "M", cover: "")
        repo.applyChapters((1...3).reversed().map { SourceChapter(url: "/c/\($0)", name: "Ch \($0)", number: Double($0), date: nil, scanlator: nil) }, to: manga)
        let middle = try XCTUnwrap(manga.chapters.first { $0.url == "/c/2" })
        let model = ReaderModel(sourceId: "s", manga: manga, start: middle)
        XCTAssertEqual(model.chapter(after: middle)?.url, "/c/3")
        XCTAssertEqual(model.chapter(before: middle)?.url, "/c/1")
        XCTAssertNil(model.chapter(after: try XCTUnwrap(manga.chapters.first { $0.url == "/c/3" })))
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
