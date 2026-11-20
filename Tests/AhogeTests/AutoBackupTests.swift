import XCTest
@testable import Ahoge

@MainActor
final class AutoBackupTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "auto-backup-tests-\(UUID().uuidString)")!
        Pref.autoBackupInterval.set(24, in: defaults)
        return defaults
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func makeStore() -> ExtensionStore {
        ExtensionStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            client: RepoClient(transport: StubTransport.text("", status: 500))
        )
    }

    private func files(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    func testWritesOneBackupWhenDueAndNoneBeforeTheInterval() async throws {
        let defaults = makeDefaults()
        let folder = try makeFolder()
        let repo = try LibraryRepository.inMemory()
        let store = makeStore()
        let wrote = await AutoBackup.runIfDue(repo: repo, store: store, defaults: defaults, folder: folder, now: now)
        XCTAssertTrue(wrote)
        XCTAssertEqual(try files(in: folder).count, 1)
        XCTAssertEqual(Pref.autoBackupLast.value(in: defaults), now.timeIntervalSince1970)
        let again = await AutoBackup.runIfDue(repo: repo, store: store, defaults: defaults, folder: folder, now: now.addingTimeInterval(3600))
        XCTAssertFalse(again)
        XCTAssertEqual(try files(in: folder).count, 1)
    }
}
