import XCTest
@testable import Ahoge

@MainActor
final class LibraryStatisticsTests: XCTestCase {
    private func title(_ repo: LibraryRepository, source: String, url: String, status: String = "ongoing", chapters: Int, readFirst: Int = 0) -> LibraryManga {
        let manga = repo.upsert(sourceId: source, url: url, title: url, cover: "")
        manga.status = status
        repo.applyChapters((1...chapters).map { SourceChapter(url: "\(url)/c/\($0)", name: "Ch \($0)", number: Double($0), date: nil, scanlator: nil) }, to: manga)
        repo.setRead(Array(manga.sortedChapters.reversed().prefix(readFirst)), true)
        return manga
    }

    func testCountsTitlesChaptersAndSources() throws {
        let repo = try LibraryRepository.inMemory()
        let one = title(repo, source: "en.demo", url: "/a", status: "completed", chapters: 4, readFirst: 3)
        let two = title(repo, source: "en.demo", url: "/b", chapters: 2)
        let three = title(repo, source: "local", url: "/c", chapters: 1, readFirst: 1)
        let seconds = [one.sortedChapters[0].key: 600, three.chapters[0].key: 90, "other\n/x": 5000]

        let stats = LibraryStatistics.compute(manga: [one, two, three], history: seconds, downloaded: [one.key: 2, two.key: 1])

        XCTAssertEqual(stats, LibraryStatistics.Stats(
            titles: 3, completed: 1, started: 2, local: 1,
            chaptersTotal: 7, chaptersRead: 4, chaptersDownloaded: 3,
            readSeconds: 690, sources: 2
        ))
    }

    func testDurationText() {
        XCTAssertEqual(LibraryStatistics.duration(0), "0 min")
        XCTAssertEqual(LibraryStatistics.duration(59 * 60 + 59), "59 min")
        XCTAssertEqual(LibraryStatistics.duration(3600), "1 h")
        XCTAssertEqual(LibraryStatistics.duration(3600 + 5 * 60), "1 h 5 min")
    }
}
