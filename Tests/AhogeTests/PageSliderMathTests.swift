import XCTest
@testable import Ahoge

final class PageSliderMathTests: XCTestCase {
    // 220pt wide: 10pt inset each side leaves a 200pt track; 11 pages are 20pt apart.
    func testEndsMapToFirstAndLastPage() {
        XCTAssertEqual(PageSliderMath.offset(page: 0, count: 11, width: 220, reversed: false), 10)
        XCTAssertEqual(PageSliderMath.offset(page: 10, count: 11, width: 220, reversed: false), 210)
        XCTAssertEqual(PageSliderMath.page(at: 0, count: 11, width: 220, reversed: false), 0)
        XCTAssertEqual(PageSliderMath.page(at: 220, count: 11, width: 220, reversed: false), 10)
    }

    func testSnapsToNearestPage() {
        XCTAssertEqual(PageSliderMath.page(at: 59, count: 11, width: 220, reversed: false), 2)
        XCTAssertEqual(PageSliderMath.page(at: 61, count: 11, width: 220, reversed: false), 3)
    }

    func testReversedMirrors() {
        XCTAssertEqual(PageSliderMath.offset(page: 0, count: 11, width: 220, reversed: true), 210)
        XCTAssertEqual(PageSliderMath.page(at: 10, count: 11, width: 220, reversed: true), 10)
    }

    func testRoundTrip() {
        for page in 0..<37 {
            let x = PageSliderMath.offset(page: page, count: 37, width: 300, reversed: false)
            XCTAssertEqual(PageSliderMath.page(at: x, count: 37, width: 300, reversed: false), page)
        }
    }

    func testSinglePage() {
        XCTAssertEqual(PageSliderMath.page(at: 150, count: 1, width: 220, reversed: false), 0)
        XCTAssertFalse(PageSliderMath.showsDots(count: 1, width: 220))
    }

    func testDotsShrinkThenHide() {
        XCTAssertEqual(PageSliderMath.dotSize(count: 11, width: 220), 4)          // 20pt apart: full size
        XCTAssertTrue(PageSliderMath.showsDots(count: 60, width: 220))            // 200/59 ≈ 3.4pt apart
        XCTAssertLessThan(PageSliderMath.dotSize(count: 60, width: 220), 2)
        XCTAssertFalse(PageSliderMath.showsDots(count: 80, width: 220))           // 200/79 ≈ 2.5pt: a solid line
    }
}
