import XCTest
@testable import Ahoge

final class MihonBackupImporterTests: XCTestCase {
    private func source(_ id: String, _ name: String, lang: String = "en") -> RepoSource {
        RepoSource(
            id: id, name: name, lang: lang, version: "1.0.0", runtime: 1, nsfw: false, baseUrl: "https://demo.test",
            icon: nil, script: "dist/\(id).js", sha256: "x", health: .init(status: "ok", checkedAt: nil)
        )
    }

    /// Two sources, one category, and two titles: a library title with history and a non-library one.
    private func mihonBackup() -> [UInt8] {
        var backup = ProtoWriter()
        backup.message(1) { manga in
            manga.int(1, 111)
            manga.string(2, "/m/1")
            manga.string(3, "One")
            manga.string(4, "Art")
            manga.string(5, "Auth")
            manga.string(6, "Desc")
            manga.string(7, "Action")
            manga.string(7, "Drama")
            manga.int(8, 1)
            manga.string(9, "https://c/1.jpg")
            manga.int(13, 1_793_600_000_000)
            manga.message(16) { chapter in
                chapter.string(1, "/c/2")
                chapter.string(2, "Ch 2")
                chapter.string(3, "Fast")
                chapter.bool(4, true)
                chapter.int(6, 11)
                chapter.int(8, 1_793_500_000_000)
                chapter.float(9, 2.5)
            }
            manga.message(16) { chapter in
                chapter.string(1, "/c/1")
                chapter.string(2, "Ch 1")
                chapter.bool(5, true)
                chapter.float(9, 1)
                chapter.int(10, 1)
            }
            manga.int(17, 3)
            manga.message(104) { history in
                history.string(1, "/c/2")
                history.int(2, 1_793_650_000_000)
                history.int(3, 300_000)
            }
            manga.string(108, "Slow")
            manga.string(110, "my note")
        }
        backup.message(1) { manga in
            manga.int(1, 222)
            manga.string(2, "/m/9")
            manga.string(3, "Nine")
            manga.bool(100, false)
        }
        backup.message(2) { category in
            category.string(1, "Reading")
            category.int(2, 3)
        }
        backup.message(101) { source in
            source.string(1, "Demo Source")
            source.int(2, 111)
        }
        backup.message(101) { source in
            source.string(1, "Gone")
            source.int(2, 222)
        }
        return backup.bytes
    }

    func testDecodesAGzippedBackup() throws {
        let file = try ProtoWriter.gzip(mihonBackup())
        let result = try MihonBackupImporter.decode(file, sources: [source("en.demo", "demo source"), source("en.other", "Other")], now: Date(timeIntervalSince1970: 5000))
        let backup = result.backup

        XCTAssertEqual(backup.manga.map(\.title), ["One", "Nine"])
        XCTAssertEqual(backup.categories, [BackupCategory(name: "Reading", sort: 0)])
        XCTAssertEqual(backup.installedSourceIds, ["en.demo"])
        XCTAssertEqual(result.unmatchedSources, ["Gone"])

        let one = backup.manga[0]
        XCTAssertEqual(one.sourceId, "en.demo")
        XCTAssertEqual(one.sourceName, "Demo Source")
        XCTAssertEqual(one.url, "/m/1")
        XCTAssertEqual(one.artist, "Art")
        XCTAssertEqual(one.author, "Auth")
        XCTAssertEqual(one.summary, "Desc")
        XCTAssertEqual(one.genres, ["Action", "Drama"])
        XCTAssertEqual(one.status, "ongoing")
        XCTAssertEqual(one.cover, "https://c/1.jpg")
        XCTAssertEqual(one.dateAdded, Date(timeIntervalSince1970: 1_793_600_000))
        XCTAssertTrue(one.inLibrary)
        XCTAssertEqual(one.categories, ["Reading"])
        XCTAssertEqual(one.excludedScanlators, ["Slow"])
        XCTAssertEqual(one.notes, "my note")

        XCTAssertEqual(one.chapters.map(\.url), ["/c/2", "/c/1"])
        let first = one.chapters[0]
        XCTAssertEqual(first.name, "Ch 2")
        XCTAssertEqual(first.number, 2.5)
        XCTAssertEqual(first.scanlator, "Fast")
        XCTAssertTrue(first.read)
        XCTAssertFalse(first.bookmark)
        XCTAssertEqual(first.lastPageRead, 11)
        XCTAssertEqual(first.dateUpload, Date(timeIntervalSince1970: 1_793_500_000))
        XCTAssertEqual(first.sourceOrder, 0, "an omitted source order is the list position")
        XCTAssertEqual(first.lastRead, Date(timeIntervalSince1970: 1_793_650_000))
        XCTAssertEqual(first.timeRead, 300)
        let second = one.chapters[1]
        XCTAssertTrue(second.bookmark)
        XCTAssertFalse(second.read)
        XCTAssertEqual(second.sourceOrder, 1)
        XCTAssertNil(second.lastRead)

        let nine = backup.manga[1]
        XCTAssertEqual(nine.sourceId, "mihon:222")
        XCTAssertEqual(nine.sourceName, "Gone")
        XCTAssertFalse(nine.inLibrary)
    }

    func testGzipHeaderWithAFileNameIsSkipped() throws {
        let file = try ProtoWriter.gzip(mihonBackup(), fileName: "backup.proto")
        let result = try MihonBackupImporter.decode(file, sources: [], now: Date(timeIntervalSince1970: 5000))
        XCTAssertEqual(result.backup.manga.map(\.title), ["One", "Nine"])
    }

    func testUncompressedProtobufIsAccepted() throws {
        let result = try MihonBackupImporter.decode(Data(mihonBackup()), sources: [], now: Date(timeIntervalSince1970: 5000))
        XCTAssertEqual(result.backup.manga.map(\.title), ["One", "Nine"])
    }

    func testSourceNameMatchIgnoresCaseAndPrefersEnglish() {
        let sources = [source("fr.demo", "MangaDemo", lang: "fr"), source("en.demo", "mangademo", lang: "en")]
        XCTAssertEqual(MihonBackupImporter.find("  MANGADEMO ", in: sources)?.id, "en.demo")
        XCTAssertEqual(MihonBackupImporter.find("MangaDemo", in: [sources[0]])?.id, "fr.demo")
        XCTAssertNil(MihonBackupImporter.find("Other", in: sources))
    }

    func testGarbageIsNotABackup() {
        XCTAssertThrowsError(try MihonBackupImporter.decode(Data(), sources: [])) { XCTAssertEqual($0 as? BackupError, .notABackup) }
        XCTAssertThrowsError(try MihonBackupImporter.decode(Data([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 0xff, 1, 2, 3]), sources: [])) {
            XCTAssertEqual($0 as? BackupError, .notABackup)
        }
        XCTAssertThrowsError(try MihonBackupImporter.decode(Data([0x0a, 0xff, 0xff]), sources: [])) { XCTAssertEqual($0 as? BackupError, .notABackup) }
    }
}
