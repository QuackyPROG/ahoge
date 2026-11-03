import GRDB
import XCTest
@testable import Ahoge

@MainActor
final class BackupServiceTests: XCTestCase {
    private func store() -> ExtensionStore {
        ExtensionStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            client: RepoClient(transport: StubTransport.text("", status: 500))
        )
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "backup-tests-\(UUID().uuidString)")!
    }

    private func chapter(_ url: String, _ number: Double) -> SourceChapter {
        SourceChapter(url: url, name: "Ch \(Int(number))", number: number, date: nil, scanlator: nil)
    }

    func testSnapshotThenRestoreIntoEmptyRepoGivesTheSameLibrary() async throws {
        let source = try LibraryRepository.inMemory()
        let one = source.upsert(sourceId: "en.demo", url: "/m/1", title: "One", cover: "https://c/1.jpg")
        source.setInLibrary(one, true)
        one.notes = "my note"
        one.updateInterval = 7
        source.write { try one.update($0) }
        source.applyChapters([chapter("/c/3", 3), chapter("/c/2", 2), chapter("/c/1", 1)], to: one)
        source.setRead([try XCTUnwrap(one.chapters.first { $0.url == "/c/1" })], true)
        let bookmarked = try XCTUnwrap(one.chapters.first { $0.url == "/c/1" })
        bookmarked.bookmark = true
        source.write { try bookmarked.update($0) }
        source.saveProgress(try XCTUnwrap(one.chapters.first { $0.url == "/c/2" }), page: 3, pageCount: 10)
        source.write { try $0.execute(sql: "INSERT INTO excludedScanlator (mangaKey, scanlator) VALUES (?, ?)", arguments: [one.key, "Slow Group"]) }
        let reading = try XCTUnwrap(source.createCategory(named: "Reading"))
        source.categories[0].flags = 2
        source.categories[0].sortMode = "Title:asc"
        let edited = source.categories[0]
        source.write { try edited.update($0) }
        source.setCategories([reading.id], for: one)

        let sourceDefaults = defaults()
        Pref.readerMode.set("paged", in: sourceDefaults)
        let backup = BackupService.snapshot(of: source, store: store(), defaults: sourceDefaults)

        let target = try LibraryRepository.inMemory()
        let targetDefaults = defaults()
        let report = await BackupService.restore(backup, into: target, store: store(), defaults: targetDefaults)

        XCTAssertEqual(report.restoredManga, 1)
        XCTAssertEqual(target.library.map(\.title), ["One"])
        let restored = try XCTUnwrap(target.manga(sourceId: "en.demo", url: "/m/1"))
        XCTAssertEqual(restored.coverUrl, "https://c/1.jpg")
        XCTAssertEqual(restored.notes, "my note")
        XCTAssertEqual(restored.updateInterval, 7)
        XCTAssertEqual(restored.sortedChapters.map(\.url), ["/c/3", "/c/2", "/c/1"])
        XCTAssertEqual(restored.sortedChapters.map(\.read), [false, false, true])
        XCTAssertEqual(restored.sortedChapters.map(\.bookmark), [false, false, true])
        XCTAssertEqual(restored.sortedChapters.map(\.lastPageRead), [0, 3, 0])
        XCTAssertEqual(target.history().first?.chapter.url, "/c/2")
        XCTAssertEqual(target.excludedScanlatorsByManga()[restored.key], ["Slow Group"])
        XCTAssertEqual(target.categories.map(\.name), ["Reading"])
        XCTAssertEqual(target.categories.first?.flags, 2)
        XCTAssertEqual(target.categories.first?.sortMode, "Title:asc")
        XCTAssertEqual(target.library(in: target.categories[0].id).map(\.title), ["One"])
        XCTAssertEqual(Pref.readerMode.value(in: targetDefaults), "paged")

        // The restored database survives a reopen: it was written, not just held in memory.
        let reloaded = try LibraryRepository(db: target.db)
        XCTAssertEqual(reloaded.library.first?.chapters.filter(\.read).count, 1)
    }

    func testMergeKeepsTheMostProgress() async throws {
        let target = try LibraryRepository.inMemory()
        let one = target.upsert(sourceId: "en.demo", url: "/m/1", title: "One", cover: "")
        target.setInLibrary(one, true)
        target.applyChapters([chapter("/c/2", 2), chapter("/c/1", 1)], to: one)
        let local1 = try XCTUnwrap(one.chapters.first { $0.url == "/c/1" })
        let local2 = try XCTUnwrap(one.chapters.first { $0.url == "/c/2" })
        local1.lastPageRead = 5
        local2.read = true
        target.write { try local1.update($0); try local2.update($0) }
        target.recordHistory(local1, at: Date(timeIntervalSince1970: 2000))
        let local = try XCTUnwrap(target.createCategory(named: "reading"))

        let backup = Backup(
            createdAt: Date(timeIntervalSince1970: 5000),
            manga: [BackupManga(
                sourceId: "en.demo", url: "/m/1", title: "One",
                categories: ["Reading"],
                chapters: [
                    BackupChapter(url: "/c/2", name: "Ch 2", number: 2, sourceOrder: 0, read: false, bookmark: true, lastPageRead: 7, lastRead: Date(timeIntervalSince1970: 3000)),
                    BackupChapter(url: "/c/1", name: "Ch 1", number: 1, sourceOrder: 1, read: true, lastPageRead: 2, lastRead: Date(timeIntervalSince1970: 1000)),
                ]
            )],
            categories: [BackupCategory(name: "Reading", sort: 0)]
        )
        _ = await BackupService.restore(backup, into: target, store: store(), defaults: defaults())

        let merged = try XCTUnwrap(target.manga(sourceId: "en.demo", url: "/m/1"))
        let c1 = try XCTUnwrap(merged.chapters.first { $0.url == "/c/1" })
        let c2 = try XCTUnwrap(merged.chapters.first { $0.url == "/c/2" })
        XCTAssertTrue(c1.read, "read on the backup side")
        XCTAssertEqual(c1.lastPageRead, 5, "local page is larger")
        XCTAssertTrue(c2.read, "read on the local side")
        XCTAssertEqual(c2.lastPageRead, 7, "backup page is larger")
        XCTAssertTrue(c2.bookmark)

        func lastRead(_ chapter: ChapterRecord) throws -> Date? {
            try target.db.read { try Date.fetchOne($0, sql: "SELECT lastRead FROM history WHERE chapterKey = ?", arguments: [chapter.key]) }
        }
        XCTAssertEqual(try lastRead(c1), Date(timeIntervalSince1970: 2000), "the newer date wins")
        XCTAssertEqual(try lastRead(c2), Date(timeIntervalSince1970: 3000))

        XCTAssertEqual(target.categories.map(\.name), ["reading"], "matched by name, ignoring case")
        XCTAssertEqual(target.categoryIds(of: merged), [local.id])
        XCTAssertEqual(target.library.count, 1)
    }

    func testTitleFromAnUninstalledSourceIsRestoredAndReported() async throws {
        let target = try LibraryRepository.inMemory()
        let backup = Backup(
            createdAt: Date(timeIntervalSince1970: 5000),
            manga: [
                BackupManga(sourceId: "en.gone", sourceName: "Gone Source", url: "/m/9", title: "Nine"),
                BackupManga(sourceId: "en.other", url: "/m/2", title: "Two"),
            ]
        )
        let report = await BackupService.restore(backup, into: target, store: store(), defaults: defaults())

        XCTAssertEqual(report.restoredManga, 2)
        XCTAssertEqual(report.missingSources, ["en.other", "Gone Source"])
        XCTAssertEqual(target.library.map(\.title).sorted(), ["Nine", "Two"])
    }

    func testRepositoryThatCannotBeReachedIsReported() async throws {
        let target = try LibraryRepository.inMemory()
        let backup = Backup(createdAt: Date(timeIntervalSince1970: 5000), repos: ["https://repo.test/index.json"])
        let report = await BackupService.restore(backup, into: target, store: store(), defaults: defaults())
        XCTAssertEqual(report.failedRepos, ["https://repo.test/index.json"])
    }

    func testOnlyListedPreferencesAreRestored() async throws {
        let target = try LibraryRepository.inMemory()
        let backup = Backup(
            createdAt: Date(timeIntervalSince1970: 5000),
            preferences: ["reader.brightness": .int(-30), "not.a.pref": .string("x")]
        )
        let restoredDefaults = defaults()
        _ = await BackupService.restore(backup, into: target, store: store(), defaults: restoredDefaults)
        XCTAssertEqual(Pref.readerBrightness.value(in: restoredDefaults), -30)
        XCTAssertNil(restoredDefaults.object(forKey: "not.a.pref"))
    }
}
