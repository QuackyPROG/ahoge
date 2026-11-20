import XCTest
@testable import Ahoge

final class SettingsSearchTests: XCTestCase {
    func testMatchesTitleWordsInAnyOrderIgnoringCase() {
        let found = SettingsIndex.search("CACHE clear").map(\.title)
        XCTAssertTrue(found.contains("Clear image cache"))
        XCTAssertTrue(found.contains("Clear chapter cache"))
        XCTAssertFalse(found.contains("Theme mode"))
    }

    func testMatchesKeywords() {
        XCTAssertTrue(SettingsIndex.search("face id").map(\.title).contains("Require unlock"))
    }

    func testMigrateOpensTheMigrateSources() {
        let entry = SettingsIndex.search("migrate").first { $0.title == "Migrate" }
        XCTAssertEqual(entry?.destination, .migrate)
    }

    func testBlankQueryFindsNothing() {
        XCTAssertTrue(SettingsIndex.search("   ").isEmpty)
    }
}
