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

    func testRotationDeletesOnlyTheOldestAutomaticBackups() async throws {
        let defaults = makeDefaults()
        Pref.autoBackupKeep.set(3, in: defaults)
        let folder = try makeFolder()
        let manual = ["ahoge_2026-11-01_10-00.ahbk", "ahoge_2026-11-02_10-00.ahbk"]
        let automatic = (1...5).map { "ahoge_auto_2026-11-0\($0)_10-00.ahbk" }
        for (index, name) in (manual + automatic).enumerated() {
            let url = folder.appendingPathComponent(name)
            try Data("old".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(index) * 1000)], ofItemAtPath: url.path)
        }
        let repo = try LibraryRepository.inMemory()
        let wrote = await AutoBackup.runIfDue(repo: repo, store: makeStore(), defaults: defaults, folder: folder, now: now)
        XCTAssertTrue(wrote)
        let remaining = try files(in: folder)
        XCTAssertEqual(remaining.filter { manual.contains($0) }, manual)
        XCTAssertEqual(remaining.filter { automatic.contains($0) }, ["ahoge_auto_2026-11-04_10-00.ahbk", "ahoge_auto_2026-11-05_10-00.ahbk"])
        XCTAssertEqual(remaining.filter { $0.hasPrefix("ahoge_auto_") }.count, 3)
    }
}
