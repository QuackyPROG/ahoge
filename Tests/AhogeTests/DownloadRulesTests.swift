import XCTest
@testable import Ahoge

@MainActor
final class DownloadRulesTests: XCTestCase {
    private func urls(_ chapters: [ChapterRecord]) -> [String] { chapters.map(\.url) }

    func testRemoveAfterReadingPicksTheNthToLastReadChapter() throws {
        let repo = try LibraryRepository.inMemory()
        let manga = SourceFixture.manga(in: repo, chapters: 5)
        repo.setRead([manga.chapter(1), manga.chapter(2), manga.chapter(3)], true)
        var prefs = DownloadRules.Settings()

        XCTAssertEqual(urls(DownloadRules.chaptersToDelete(after: manga.chapter(3), in: manga.chapters, prefs: prefs)), [])
        prefs.removeAfterReading = 1
        XCTAssertEqual(urls(DownloadRules.chaptersToDelete(after: manga.chapter(3), in: manga.chapters, prefs: prefs)), ["/c/3"])
        prefs.removeAfterReading = 2
        XCTAssertEqual(urls(DownloadRules.chaptersToDelete(after: manga.chapter(3), in: manga.chapters, prefs: prefs)), ["/c/2"])
        prefs.removeAfterReading = 4
        XCTAssertEqual(urls(DownloadRules.chaptersToDelete(after: manga.chapter(3), in: manga.chapters, prefs: prefs)), [], "nothing that far back")

        prefs.removeAfterReading = 2
        manga.chapter(2).bookmark = true
        XCTAssertEqual(urls(DownloadRules.chaptersToDelete(after: manga.chapter(3), in: manga.chapters, prefs: prefs)), [])
        prefs.removeBookmarked = true
        XCTAssertEqual(urls(DownloadRules.chaptersToDelete(after: manga.chapter(3), in: manga.chapters, prefs: prefs)), ["/c/2"])
    }

    func testRemoveAfterMarkedReadKeepsBookmarksUnlessAsked() throws {
        let repo = try LibraryRepository.inMemory()
        let manga = SourceFixture.manga(in: repo, chapters: 2)
        manga.chapter(1).bookmark = true
        let marked = [manga.chapter(1), manga.chapter(2)]
        var prefs = DownloadRules.Settings()

        XCTAssertEqual(urls(DownloadRules.chaptersToDelete(markedRead: marked, prefs: prefs)), [])
        prefs.removeAfterMarkedRead = true
        XCTAssertEqual(urls(DownloadRules.chaptersToDelete(markedRead: marked, prefs: prefs)), ["/c/2"])
        prefs.removeBookmarked = true
        XCTAssertEqual(urls(DownloadRules.chaptersToDelete(markedRead: marked, prefs: prefs)), ["/c/1", "/c/2"])
    }

    func testDownloadAheadNeedsTheOpenAndNextChapterDownloaded() throws {
        let repo = try LibraryRepository.inMemory()
        let manga = SourceFixture.manga(in: repo, chapters: 6)
        repo.setRead([manga.chapter(4)], true)
        var prefs = DownloadRules.Settings()
        prefs.downloadAhead = 2
        let both: Set<String> = [manga.chapter(1).key, manga.chapter(2).key]

        XCTAssertEqual(urls(DownloadRules.chaptersToDownloadAhead(current: manga.chapter(1), in: manga.chapters, inLibrary: true, downloaded: both, prefs: prefs)), ["/c/3", "/c/5"])
        XCTAssertEqual(urls(DownloadRules.chaptersToDownloadAhead(current: manga.chapter(1), in: manga.chapters, inLibrary: true, downloaded: [manga.chapter(1).key], prefs: prefs)), [])
        XCTAssertEqual(urls(DownloadRules.chaptersToDownloadAhead(current: manga.chapter(1), in: manga.chapters, inLibrary: false, downloaded: both, prefs: prefs)), [])
        prefs.downloadAhead = 0
        XCTAssertEqual(urls(DownloadRules.chaptersToDownloadAhead(current: manga.chapter(1), in: manga.chapters, inLibrary: true, downloaded: both, prefs: prefs)), [])
    }

    func testNewChaptersDownloadUnlessOffOrInAnExcludedCategory() throws {
        let repo = try LibraryRepository.inMemory()
        let manga = SourceFixture.manga(in: repo, chapters: 3)
        repo.setRead([manga.chapter(2)], true)
        let new = [manga.chapter(3), manga.chapter(2)]
        let plain = MangaCategory(id: 1, name: "Reading", sort: 0, flags: 0)
        let excluded = MangaCategory(id: 2, name: "Done", sort: 1, flags: 2)
        var prefs = DownloadRules.Settings()

        XCTAssertEqual(urls(DownloadRules.chaptersToAutoDownload(new: new, manga: manga, categories: [plain], prefs: prefs)), [])
        prefs.downloadNew = true
        XCTAssertEqual(urls(DownloadRules.chaptersToAutoDownload(new: new, manga: manga, categories: [plain], prefs: prefs)), ["/c/3"])
        XCTAssertEqual(urls(DownloadRules.chaptersToAutoDownload(new: new, manga: manga, categories: [plain, excluded], prefs: prefs)), [])
        repo.setInLibrary(manga, false)
        XCTAssertEqual(urls(DownloadRules.chaptersToAutoDownload(new: new, manga: manga, categories: [], prefs: prefs)), [])
    }
}
