import SwiftData
import XCTest
@testable import Ahoge

@MainActor
final class LibraryRepositoryTests: XCTestCase {
    private func repository() throws -> LibraryRepository {
        let container = try ModelContainer(for: LibraryManga.self, ChapterRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return LibraryRepository(context: container.mainContext)
    }

    private func chapter(_ url: String, _ number: Double) -> SourceChapter {
        SourceChapter(url: url, name: "Ch \(Int(number))", number: number, date: nil, scanlator: nil)
    }

    func testUpsertLibraryAndChapters() throws {
        let repo = try repository()
        let manga = repo.upsert(sourceId: "en.demo", url: "/m/1", title: "One", cover: "https://c/1.jpg")
        XCTAssertFalse(manga.inLibrary)
        repo.setInLibrary(manga, true)
        XCTAssertNotNil(manga.dateAdded)
        XCTAssertTrue(repo.manga(sourceId: "en.demo", url: "/m/1") === manga)

        repo.applyChapters([chapter("/c/3", 3), chapter("/c/2", 2), chapter("/c/1", 1)], to: manga)
        XCTAssertEqual(manga.sortedChapters.map(\.url), ["/c/3", "/c/2", "/c/1"])
        XCTAssertEqual(manga.unreadCount, 3)

        repo.markPreviousRead(try XCTUnwrap(manga.sortedChapters.first { $0.url == "/c/2" }), in: manga)
        XCTAssertEqual(manga.sortedChapters.map(\.read), [false, true, true])

        repo.saveProgress(try XCTUnwrap(manga.sortedChapters.first), page: 4, pageCount: 5)
        XCTAssertEqual(manga.sortedChapters.first?.read, true)
        XCTAssertNotNil(manga.lastReadAt)

        repo.applyChapters([chapter("/c/4", 4), chapter("/c/3", 3), chapter("/c/2", 2)], to: manga)
        XCTAssertEqual(manga.sortedChapters.map(\.url), ["/c/4", "/c/3", "/c/2"])
        XCTAssertEqual(manga.sortedChapters.map(\.read), [false, true, true])
    }

    func testDetailsUpdateKeepsLibraryFlag() throws {
        let repo = try repository()
        let manga = repo.upsert(sourceId: "en.demo", url: "/m/1", title: "One", cover: "")
        repo.setInLibrary(manga, true)
        let details = try JSONDecoder().decode(MangaDetails.self, from: Data(#"{"title":"One Full","cover":"https://c/big.jpg","author":"A","artist":"B","description":"D","genres":["Action"],"status":"ongoing"}"#.utf8))
        let updated = repo.upsert(sourceId: "en.demo", url: "/m/1", details: details)
        XCTAssertTrue(updated === manga)
        XCTAssertTrue(updated.inLibrary)
        XCTAssertEqual(updated.title, "One Full")
        XCTAssertEqual(updated.genres, ["Action"])
    }
}
