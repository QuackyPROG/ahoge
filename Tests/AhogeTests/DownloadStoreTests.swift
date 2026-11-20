import XCTest
@testable import Ahoge

final class DownloadStoreTests: XCTestCase {
    func testCancelledZipLeavesNoArchiveTemporaryFileOrFolder() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = DownloadStore(root: base.appendingPathComponent("downloads"), cache: base.appendingPathComponent("cache"))
        let location = DownloadStore.Location(sourceId: "en.test", mangaKey: "en.test\n/m", chapterKey: "en.test\n/c/1")
        let directory = try store.begin(location, pages: ["https://img.test/1.jpg", "https://img.test/2.jpg"])
        for name in ["001.jpg", "002.jpg"] { try Data([0xFF, 0xD8, 0xFF]).write(to: directory.appendingPathComponent(name)) }

        XCTAssertThrowsError(try store.finish(location, pages: 2, zip: true, isCancelled: { true })) { error in
            XCTAssertTrue(error is CancellationError)
        }

        let fm = FileManager.default
        XCTAssertFalse(fm.fileExists(atPath: store.archive(location).path))
        XCTAssertFalse(fm.fileExists(atPath: store.archive(location).appendingPathExtension("tmp").path))
        XCTAssertFalse(fm.fileExists(atPath: directory.path))
    }
}
