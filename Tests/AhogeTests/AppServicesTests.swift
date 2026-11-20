import XCTest
@testable import Ahoge

@MainActor
final class AppServicesTests: XCTestCase {
    private func makeServices(database: URL) -> AppServices {
        let store = ExtensionStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            client: RepoClient(transport: StubTransport.text("", status: 500))
        )
        return AppServices(extensions: store, sources: SourceManager(extensions: store)) { try LibraryRepository.open(at: database) }
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func testLoadsFromADatabaseFile() throws {
        let services = makeServices(database: try makeFolder().appendingPathComponent("library.sqlite"))
        guard case .loaded = services.state else { return XCTFail("expected loaded, got \(services.state)") }
    }

    func testReportsTheErrorThenRetrySucceedsOnceThePathIsFixed() throws {
        // A directory where the database file should be cannot open as SQLite.
        let database = try makeFolder()
        let services = makeServices(database: database)
        guard case .failed(let error) = services.state else { return XCTFail("expected failed, got \(services.state)") }
        XCTAssertFalse(error.localizedDescription.isEmpty)
        try FileManager.default.removeItem(at: database)
        services.load()
        guard case .loaded = services.state else { return XCTFail("expected loaded, got \(services.state)") }
    }
}
