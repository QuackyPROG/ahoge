import XCTest
@testable import Ahoge

final class BackupCodecTests: XCTestCase {
    private func sample() -> Backup {
        Backup(
            createdAt: Date(timeIntervalSince1970: 1_793_700_000),
            manga: [BackupManga(
                sourceId: "en.demo", url: "/m/1", title: "One", genres: ["Action"], notes: "note",
                categories: ["Reading"], excludedScanlators: ["Slow"],
                chapters: [BackupChapter(url: "/c/1", name: "Ch 1", number: 1, read: true, bookmark: true, lastPageRead: 4, lastRead: Date(timeIntervalSince1970: 1_793_650_000), timeRead: 90)]
            )],
            categories: [BackupCategory(name: "Reading", sort: 0, flags: 2, sortMode: "Title:asc")],
            repos: ["https://repo.test/index.json"],
            installedSourceIds: ["en.demo"],
            preferences: ["reader.dim": .double(0.5), "reader.keepScreenOn": .bool(false), "library.shelf": .int(1), "reader.mode.default": .string("paged"), "browse.pinnedSources": .strings(["a", "b"])]
        )
    }

    func testRoundTrip() throws {
        let backup = sample()
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(backup)), backup)
    }

    func testGarbageIsNotABackup() {
        XCTAssertThrowsError(try BackupCodec.decode(Data("hello".utf8))) { XCTAssertEqual($0 as? BackupError, .notABackup) }
        XCTAssertThrowsError(try BackupCodec.decode(Data("AHBK1garbage".utf8))) { XCTAssertEqual($0 as? BackupError, .notABackup) }
        XCTAssertThrowsError(try BackupCodec.decode(Data())) { XCTAssertEqual($0 as? BackupError, .notABackup) }
    }

    func testNewerVersionIsRefused() throws {
        var backup = sample()
        backup.version = 99
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(backup))) { XCTAssertEqual($0 as? BackupError, .newerVersion(99)) }
    }

    /// The version 1 field names, written by hand. If this fails, old backups would stop restoring.
    func testGoldenVersion1Payload() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "backup-v1", withExtension: "json"))
        let backup = try BackupCodec.decodePayload(Data(contentsOf: url))

        XCTAssertEqual(backup.version, 1)
        XCTAssertEqual(backup.createdAt, Date(timeIntervalSince1970: 1_793_700_000))
        XCTAssertEqual(backup.repos, ["https://repo.test/index.json"])
        XCTAssertEqual(backup.installedSourceIds, ["en.demo"])
        XCTAssertEqual(backup.categories, [BackupCategory(name: "Reading", sort: 0, flags: 1, sortMode: "Title:asc")])
        XCTAssertEqual(backup.preferences["reader.mode.default"], .string("paged"))
        XCTAssertEqual(backup.preferences["reader.keepScreenOn"], .bool(false))
        XCTAssertEqual(backup.preferences["reader.dim"], .double(0.25))
        XCTAssertEqual(backup.preferences["library.shelf"], .int(2))
        XCTAssertEqual(backup.preferences["browse.pinnedSources"], .strings(["en.demo"]))

        let manga = try XCTUnwrap(backup.manga.first)
        XCTAssertEqual(manga.sourceId, "en.demo")
        XCTAssertEqual(manga.url, "/m/1")
        XCTAssertEqual(manga.title, "One")
        XCTAssertEqual(manga.genres, ["Action", "Drama"])
        XCTAssertEqual(manga.notes, "my note")
        XCTAssertEqual(manga.updateInterval, 7)
        XCTAssertEqual(manga.categories, ["Reading"])
        XCTAssertEqual(manga.excludedScanlators, ["Slow Group"])
        XCTAssertEqual(manga.dateAdded, Date(timeIntervalSince1970: 1_793_600_000))
        XCTAssertEqual(manga.chapters.count, 2)
        let read = manga.chapters[0]
        XCTAssertEqual(read.url, "/c/2")
        XCTAssertEqual(read.scanlator, "Fast Group")
        XCTAssertTrue(read.read)
        XCTAssertTrue(read.bookmark)
        XCTAssertEqual(read.lastPageRead, 11)
        XCTAssertEqual(read.lastRead, Date(timeIntervalSince1970: 1_793_650_000))
        XCTAssertEqual(read.timeRead, 300)
        XCTAssertNil(manga.chapters[1].lastRead)
    }
}
