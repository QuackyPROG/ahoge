import XCTest
@testable import Ahoge

final class DetailPaneWidthTests: XCTestCase {
    // iPad Split View at its narrowest regular width: the chapter list keeps at least half.
    func testNarrowRegularWidthLeavesChaptersTheLargerPart() {
        let pane = DetailPaneWidth.width(available: 507)
        XCTAssertLessThanOrEqual(pane, 253)
        XCTAssertGreaterThanOrEqual(507 - pane, pane)
    }

    // A full-width 13-inch iPad in landscape: capped at 400 pt.
    func testWideScreenCapsAt400() {
        XCTAssertEqual(DetailPaneWidth.width(available: 1366), 400)
    }

    // Between the two, the pane takes about 40 % of the width.
    func testMiddleWidthTakesFortyPercent() {
        XCTAssertEqual(DetailPaneWidth.width(available: 820), 328, accuracy: 0.001)
    }

    func testNeverWiderThanHalf() {
        for available in stride(from: CGFloat(0), through: 2000, by: 25) {
            XCTAssertLessThanOrEqual(DetailPaneWidth.width(available: available), available / 2)
        }
    }
}
