import GRDB
import UIKit
import XCTest
@testable import Ahoge

@MainActor
final class EntryScreenTests: XCTestCase {
    private func chapter(_ url: String, _ number: Double, scanlator: String? = nil) -> SourceChapter {
        SourceChapter(url: url, name: "Ch \(Int(number))", number: number, date: nil, scanlator: scanlator)
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let name = "EntryScreenTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func pngData() throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 6)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 6))
        }
        return try XCTUnwrap(image.pngData())
    }

    // MARK: Chapter display

    func testBookmarkedFilterIncludesOrExcludes() throws {
        let repo = try LibraryRepository.inMemory()
        let manga = repo.upsert(sourceId: "s", url: "/m", title: "M", cover: "")
        repo.applyChapters([chapter("/c/3", 3), chapter("/c/2", 2), chapter("/c/1", 1)], to: manga)
        repo.setBookmark(manga.chapters.filter { $0.url == "/c/2" }, true)

        var display = ChapterDisplay()
        display.bookmarked = .include
        XCTAssertEqual(display.apply(to: manga.chapters).map(\.url), ["/c/2"])
        display.bookmarked = .exclude
        XCTAssertEqual(display.apply(to: manga.chapters).map(\.url), ["/c/3", "/c/1"])
    }

    func testExcludedScanlatorsAreLeftOutOfTheList() throws {
        let repo = try LibraryRepository.inMemory()
        let manga = repo.upsert(sourceId: "s", url: "/m", title: "M", cover: "")
        repo.applyChapters([
            chapter("/c/3", 3, scanlator: "Fast"), chapter("/c/2", 2, scanlator: "Slow"), chapter("/c/1", 1),
        ], to: manga)

        XCTAssertEqual(ChapterDisplay().apply(to: manga.chapters, excluding: ["Slow"]).map(\.url), ["/c/3", "/c/1"])
        XCTAssertEqual(ChapterDisplay().apply(to: manga.chapters).map(\.url), ["/c/3", "/c/2", "/c/1"])
    }

    func testNumberedTitlesFallBackToTheNameWhenTheNumberIsUnknown() throws {
        let repo = try LibraryRepository.inMemory()
        let manga = repo.upsert(sourceId: "s", url: "/m", title: "M", cover: "")
        repo.applyChapters([
            SourceChapter(url: "/c/2", name: "Final Showdown", number: 12.5, date: nil, scanlator: nil),
            SourceChapter(url: "/c/1", name: "Prologue", number: -1, date: nil, scanlator: nil),
        ], to: manga)
        var display = ChapterDisplay()
        XCTAssertEqual(manga.sortedChapters.map(display.title(of:)), ["Final Showdown", "Prologue"])
        display.numberTitles = true
        XCTAssertEqual(manga.sortedChapters.map(display.title(of:)), ["Chapter 12.5", "Prologue"])
    }

    func testDisplayDefaultAppliesToMangaWithoutTheirOwn() throws {
        let defaults = try isolatedDefaults()
        let custom = ChapterDisplay(sort: .number, ascending: true, filter: .unread)
        ChapterDisplay(sort: .date).save(for: "own", to: defaults)
        custom.saveAsDefault(to: defaults)

        XCTAssertEqual(ChapterDisplay.load(for: "other", from: defaults), custom)
        XCTAssertEqual(ChapterDisplay.load(for: "own", from: defaults), ChapterDisplay(sort: .date))

        custom.saveAsDefault(clearing: ["own"], to: defaults)
        XCTAssertEqual(ChapterDisplay.load(for: "own", from: defaults), custom)
        // A manga set back to the built-in display keeps that choice against a different default.
        ChapterDisplay().save(for: "plain", to: defaults)
        XCTAssertEqual(ChapterDisplay.load(for: "plain", from: defaults), ChapterDisplay())
    }

    func testDisplaySavedByAnOlderVersionStillLoads() throws {
        let defaults = try isolatedDefaults()
        defaults.set(Data(#"{"sort":"number","ascending":true,"filter":"read"}"#.utf8), forKey: "chapterDisplay.old")
        XCTAssertEqual(ChapterDisplay.load(for: "old", from: defaults), ChapterDisplay(sort: .number, ascending: true, filter: .read))
    }

    func testMissingChaptersBetweenNeighbours() {
        XCTAssertEqual(ChapterGaps.missing(between: 10, and: 7), 2)
        XCTAssertEqual(ChapterGaps.missing(between: 7, and: 10), 2)
        XCTAssertEqual(ChapterGaps.missing(between: 8, and: 7), 0)
        XCTAssertEqual(ChapterGaps.missing(between: 7.5, and: 7), 0)
        XCTAssertEqual(ChapterGaps.missing(between: 9.5, and: 7), 1)
        XCTAssertEqual(ChapterGaps.missing(between: 7, and: 7), 0)
        XCTAssertEqual(ChapterGaps.missing(between: -1, and: 7), 0)
    }

    // MARK: Repository

    func testExcludedScanlatorsAreReplacedAndHideUpdates() throws {
        let repo = try LibraryRepository.inMemory()
        let manga = repo.upsert(sourceId: "s", url: "/m", title: "M", cover: "")
        repo.applyChapters([chapter("/c/1", 1)], to: manga)
        repo.setInLibrary(manga, true)
        repo.applyChapters([chapter("/c/3", 3, scanlator: "Slow"), chapter("/c/2", 2, scanlator: "Fast"), chapter("/c/1", 1)], to: manga)
        XCTAssertEqual(repo.updates(since: .distantPast).map(\.chapter.url), ["/c/3", "/c/2"])

        repo.setExcludedScanlators(["Slow"], for: manga)
        XCTAssertEqual(repo.excludedScanlators(mangaKey: manga.key), ["Slow"])
        XCTAssertEqual(repo.updates(since: .distantPast).map(\.chapter.url), ["/c/2"])

        repo.setExcludedScanlators(["Fast"], for: manga)
        XCTAssertEqual(repo.excludedScanlators(mangaKey: manga.key), ["Fast"])
        repo.setExcludedScanlators([], for: manga)
        XCTAssertEqual(repo.excludedScanlators(mangaKey: manga.key), [])
        XCTAssertEqual(repo.updates(since: .distantPast).map(\.chapter.url), ["/c/3", "/c/2"])
    }

    func testNewChapterWithAReadNumberIsMarkedReadWhenEnabled() throws {
        for enabled in [false, true] {
            let repo = try LibraryRepository.inMemory()
            let defaults = try isolatedDefaults()
            Pref.markDuplicateRead.set(enabled, in: defaults)
            repo.preferences = defaults
            let manga = repo.upsert(sourceId: "s", url: "/m", title: "M", cover: "")
            repo.applyChapters([chapter("/c/2", 2, scanlator: "A"), chapter("/c/1", 1, scanlator: "A")], to: manga)
            repo.setRead(manga.chapters.filter { $0.number == 2 }, true)

            repo.applyChapters([
                chapter("/d/3", 3, scanlator: "B"), chapter("/d/2", 2, scanlator: "B"),
                chapter("/c/2", 2, scanlator: "A"), chapter("/c/1", 1, scanlator: "A"),
            ], to: manga)

            let read = Dictionary(uniqueKeysWithValues: manga.chapters.map { ($0.url, $0.read) })
            XCTAssertEqual(read["/d/2"], enabled)
            XCTAssertEqual(read["/d/3"], false)
            XCTAssertEqual(read["/c/1"], false)
        }
    }

    func testNotesPersist() throws {
        let queue = try DatabaseQueue()
        let repo = try LibraryRepository(db: queue)
        let manga = repo.upsert(sourceId: "s", url: "/m", title: "M", cover: "")
        repo.setNotes("**read** later", for: manga)
        XCTAssertEqual(try LibraryRepository(db: queue).manga(key: manga.key)?.notes, "**read** later")
    }

    func testCustomCoverIsPreferredAndResets() throws {
        let repo = try LibraryRepository.inMemory()
        let manga = repo.upsert(sourceId: "s", url: "/m", title: "M", cover: "https://c/1.jpg")
        XCTAssertEqual(manga.displayCover, "https://c/1.jpg")

        XCTAssertFalse(repo.setCustomCover(Data("not an image".utf8), for: manga))
        XCTAssertTrue(repo.setCustomCover(try pngData(), for: manga))
        let name = try XCTUnwrap(manga.customCover)
        XCTAssertTrue(name.hasSuffix(".jpg"))
        XCTAssertTrue(manga.displayCover.hasPrefix("file:"))
        XCTAssertEqual(manga.ref.cover, manga.displayCover)
        XCTAssertEqual(manga.coverUrl, "https://c/1.jpg")

        repo.resetCover(of: manga)
        XCTAssertNil(manga.customCover)
        XCTAssertEqual(manga.displayCover, "https://c/1.jpg")
        XCTAssertFalse(CoverStore.exists(name))
    }

    func testCustomCoverTravelsInABackup() throws {
        let source = try LibraryRepository.inMemory()
        let manga = source.upsert(sourceId: "s", url: "/m", title: "M", cover: "https://c/1.jpg")
        source.setInLibrary(manga, true)
        XCTAssertTrue(source.setCustomCover(try pngData(), for: manga))
        defer { source.resetCover(of: manga) }

        let store = ExtensionStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            client: RepoClient(transport: StubTransport.text("", status: 500))
        )
        let backup = BackupService.snapshot(of: source, store: store, defaults: try isolatedDefaults())
        let encoded = try XCTUnwrap(backup.manga.first?.customCoverData)
        XCTAssertFalse(encoded.isEmpty)
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(backup)), backup)

        let target = try LibraryRepository.inMemory()
        target.restoreManga(try XCTUnwrap(backup.manga.first))
        let restored = try XCTUnwrap(target.manga(sourceId: "s", url: "/m"))
        XCTAssertEqual(restored.customCover, manga.customCover)
    }
}
