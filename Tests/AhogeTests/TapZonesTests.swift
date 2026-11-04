import XCTest
@testable import Ahoge

final class TapZonesTests: XCTestCase {
    private let screen = CGSize(width: 300, height: 600)

    private func action(_ x: CGFloat, _ y: CGFloat, _ layout: TapZoneLayout, inverted: Bool = false) -> TapAction {
        TapZones.action(at: CGPoint(x: x, y: y), size: screen, layout: layout, inverted: inverted)
    }

    func testDefaultIsLShaped() {
        XCTAssertEqual(action(250, 50, .standard), .previous)   // top row, even on the right
        XCTAssertEqual(action(30, 300, .standard), .previous)   // left middle
        XCTAssertEqual(action(150, 300, .standard), .menu)      // centre
        XCTAssertEqual(action(270, 300, .standard), .next)      // right middle
        XCTAssertEqual(action(30, 550, .standard), .next)       // bottom row, even on the left
    }

    func testKindleLeavesTheTopForTheMenu() {
        XCTAssertEqual(action(30, 50, .kindle), .menu)
        XCTAssertEqual(action(30, 400, .kindle), .previous)
        XCTAssertEqual(action(150, 400, .kindle), .next)
    }

    func testEdgeTurnsOnFromBothSides() {
        XCTAssertEqual(action(10, 100, .edge), .next)
        XCTAssertEqual(action(290, 100, .edge), .next)
        XCTAssertEqual(action(150, 550, .edge), .previous)
        XCTAssertEqual(action(150, 100, .edge), .menu)
    }

    func testRightAndLeftAndDisabled() {
        XCTAssertEqual(action(10, 300, .rightAndLeft), .previous)
        XCTAssertEqual(action(300, 300, .rightAndLeft), .next)   // the far edge itself
        XCTAssertEqual(action(150, 300, .rightAndLeft), .menu)
        XCTAssertEqual(action(10, 300, .disabled), .menu)
    }

    func testInvertedSwapsBackAndOn() {
        XCTAssertEqual(action(10, 300, .rightAndLeft, inverted: true), .next)
        XCTAssertEqual(action(290, 300, .rightAndLeft, inverted: true), .previous)
        XCTAssertEqual(action(150, 300, .rightAndLeft, inverted: true), .menu)
    }
}
