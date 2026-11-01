import CryptoKit
import XCTest
@testable import Ahoge

@MainActor
final class ExtensionStoreTests: XCTestCase {
    private let indexURL = "https://repo.test/index.json"
    private let script = "var source = null;\nsource = {};\n"
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func sha(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func index(version: String = "1.0.0", runtime: Int = 1, sha256: String? = nil, health: String = "ok") -> String {
        """
        {"schema":1,"name":"Test Repo","sources":[{"id":"en.demo","name":"Demo","lang":"en","version":"\(version)","runtime":\(runtime),
        "nsfw":false,"baseUrl":"https://demo.test","icon":"icons/en.demo.png","script":"dist/en.demo.js","sha256":"\(sha256 ?? sha(script))",
        "health":{"status":"\(health)","checkedAt":null}}]}
        """
    }

    private func stub(index: @escaping () -> String, script: @escaping () -> String) -> StubTransport {
        StubTransport { request in
            switch request.url?.absoluteString {
            case "https://repo.test/index.json": return (200, [:], Data(index().utf8), nil)
            case "https://repo.test/dist/en.demo.js": return (200, [:], Data(script().utf8), nil)
            default: return (404, [:], Data(), nil)
            }
        }
    }

    func testAddInstallPersistAndUninstall() async throws {
        let store = ExtensionStore(directory: directory, client: RepoClient(transport: stub(index: { self.index() }, script: { self.script })))
        try await store.addRepo(indexURL)
        XCTAssertEqual(store.repos.map(\.name), ["Test Repo"])
        XCTAssertEqual(store.rows().map(\.state), [.available])
        XCTAssertEqual(store.rows().first?.iconURL, "https://repo.test/icons/en.demo.png")

        try await store.install(try XCTUnwrap(store.rows().first?.source), from: indexURL)
        XCTAssertEqual(store.rows().map(\.state), [.installed])
        XCTAssertEqual(try store.scriptText(for: "en.demo"), script)

        let reloaded = ExtensionStore(directory: directory, client: RepoClient(transport: StubTransport.text("", status: 500)))
        XCTAssertEqual(reloaded.installed.map(\.id), ["en.demo"])
        XCTAssertEqual(reloaded.rows().map(\.state), [.installed])

        reloaded.uninstall("en.demo")
        XCTAssertTrue(reloaded.installed.isEmpty)
        XCTAssertThrowsError(try reloaded.scriptText(for: "en.demo"))
    }

    func testUpdateDetectionAndShaMismatch() async throws {
        var currentIndex = index()
        var currentScript = script
        let store = ExtensionStore(directory: directory, client: RepoClient(transport: stub(index: { currentIndex }, script: { currentScript })))
        try await store.addRepo(indexURL)
        try await store.install(try XCTUnwrap(store.rows().first?.source), from: indexURL)

        currentScript = "var source = {}; // v2\n"
        currentIndex = index(version: "1.0.1", sha256: sha(currentScript))
        await store.refresh()
        XCTAssertEqual(store.rows().map(\.state), [.updateAvailable])

        currentIndex = index(version: "1.0.2", sha256: String(repeating: "0", count: 64))
        await store.refresh()
        do {
            try await store.install(try XCTUnwrap(store.rows().first?.source), from: indexURL)
            XCTFail("expected a checksum error")
        } catch RepoError.checksumMismatch {}
    }

    func testRuntimeGateAndInvalidRepo() async throws {
        let store = ExtensionStore(directory: directory, client: RepoClient(transport: stub(index: { self.index(runtime: 2) }, script: { self.script })))
        try await store.addRepo(indexURL)
        XCTAssertEqual(store.rows().map(\.state), [.requiresAppUpdate])
        do {
            try await store.install(try XCTUnwrap(store.rows().first?.source), from: indexURL)
            XCTFail("expected a runtime error")
        } catch RepoError.requiresNewerApp {}

        do {
            try await store.addRepo("https://repo.test/missing.json")
            XCTFail("expected an invalid repo error")
        } catch {}
        XCTAssertEqual(store.repos.count, 1)
    }
}
