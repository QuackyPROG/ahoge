import XCTest
@testable import Ahoge

final class StringExtensionsTests: XCTestCase {
    func testUniquedKeepsTheFirstOfEachInOrder() {
        XCTAssertEqual(["a", "b", "a"].uniqued(), ["a", "b"])
    }
}
