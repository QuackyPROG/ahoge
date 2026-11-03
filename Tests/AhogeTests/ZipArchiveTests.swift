import XCTest
@testable import Ahoge

final class ZipArchiveTests: XCTestCase {
    private var directory: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: directory)
    }

    func testRoundTripKeepsNamesOrderAndBytes() throws {
        let url = directory.appendingPathComponent("chapter.cbz")
        let files: [(name: String, data: Data)] = [
            (name: "002.jpg", data: Data([0xFF, 0xD8, 0x00, 0x01])),
            (name: "001.png", data: Data("page one".utf8)),
            (name: "empty.txt", data: Data()),
            (name: "ページ.webp", data: Data(repeating: 7, count: 70_000)),
        ]

        try ZipArchive.write(files: files, to: url)
        let entries = try ZipArchive.entries(at: url)

        XCTAssertEqual(entries.map(\.name), files.map(\.name))
        XCTAssertFalse(entries.contains { $0.isDirectory })
        for (entry, file) in zip(entries, files) {
            XCTAssertEqual(try ZipArchive.extract(entry, from: url), file.data)
        }
    }

    func testExtractAllWritesFilesAndFolders() throws {
        let url = directory.appendingPathComponent("a.zip")
        try ZipArchive.write(files: [(name: "Ch 1/1.jpg", data: Data("one".utf8)), (name: "Ch 1/sub/", data: Data())], to: url)
        let target = directory.appendingPathComponent("out")

        try ZipArchive.extractAll(from: url, to: target)

        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("Ch 1/1.jpg")), Data("one".utf8))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(fm.fileExists(atPath: target.appendingPathComponent("Ch 1/sub").path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    /// Made with `printf 'hello hello hello hello' > a.txt && zip -9 -X t.zip a.txt`: one deflated entry.
    func testReadsADeflatedArchiveFromInfoZip() throws {
        let bytes: [UInt8] = [
            0x50, 0x4b, 0x03, 0x04, 0x14, 0x00, 0x02, 0x00, 0x08, 0x00, 0x69, 0x0d,
            0x64, 0x5d, 0xe3, 0x51, 0x3d, 0x8d, 0x0a, 0x00, 0x00, 0x00, 0x17, 0x00,
            0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x61, 0x2e, 0x74, 0x78, 0x74, 0xcb,
            0x48, 0xcd, 0xc9, 0xc9, 0x57, 0xc8, 0x40, 0x27, 0x01, 0x50, 0x4b, 0x01,
            0x02, 0x1e, 0x03, 0x14, 0x00, 0x02, 0x00, 0x08, 0x00, 0x69, 0x0d, 0x64,
            0x5d, 0xe3, 0x51, 0x3d, 0x8d, 0x0a, 0x00, 0x00, 0x00, 0x17, 0x00, 0x00,
            0x00, 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
            0x00, 0xa4, 0x81, 0x00, 0x00, 0x00, 0x00, 0x61, 0x2e, 0x74, 0x78, 0x74,
            0x50, 0x4b, 0x05, 0x06, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
            0x33, 0x00, 0x00, 0x00, 0x2d, 0x00, 0x00, 0x00, 0x00, 0x00,
        ]
        let url = directory.appendingPathComponent("t.zip")
        try Data(bytes).write(to: url)

        let entries = try ZipArchive.entries(at: url)

        XCTAssertEqual(entries.map(\.name), ["a.txt"])
        XCTAssertEqual(String(decoding: try ZipArchive.extract(entries[0], from: url), as: UTF8.self), "hello hello hello hello")
    }

    func testCRC32MatchesTheStandardCheckValue() {
        XCTAssertEqual(ZipArchive.crc32(Data("123456789".utf8)), 0xCBF4_3926)
    }

    func testRejectsNamesThatEscapeTheFolder() throws {
        for name in ["../evil.jpg", "a/../../evil.jpg", "/etc/evil", "..\\evil.jpg", "C:/evil.jpg"] {
            let url = directory.appendingPathComponent("evil.zip")
            try ZipArchive.write(files: [(name: name, data: Data("x".utf8))], to: url)
            XCTAssertThrowsError(try ZipArchive.extractAll(from: url, to: directory.appendingPathComponent("out")), name)
        }
        XCTAssertFalse(fm.fileExists(atPath: directory.deletingLastPathComponent().appendingPathComponent("evil.jpg").path))
        XCTAssertEqual(try ZipArchive.safeComponents("./a/b.jpg"), ["a", "b.jpg"])
    }

    func testNotAZipThrows() throws {
        let url = directory.appendingPathComponent("plain.cbz")
        try Data("not an archive at all, just text".utf8).write(to: url)
        XCTAssertThrowsError(try ZipArchive.entries(at: url))
    }
}
