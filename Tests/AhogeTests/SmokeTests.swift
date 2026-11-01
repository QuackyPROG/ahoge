import XCTest
@testable import Ahoge

final class SmokeTests: XCTestCase {
    func testAppNameIsAhoge() {
        XCTAssertEqual(AppInfo.name, "Ahoge")
    }
}
