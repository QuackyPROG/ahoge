import XCTest
@testable import Ahoge

final class PagePairingTests: XCTestCase {
    private let wide = CGSize(width: 2000, height: 1400)

    func testPairsInReadingOrder() {
        XCTAssertEqual(PagePairing.pairs(pages: 5, sizes: [:], rtl: false, firstAlone: false), [[0, 1], [2, 3], [4]])
        XCTAssertEqual(PagePairing.pairs(pages: 4, sizes: [:], rtl: true, firstAlone: false), [[1, 0], [3, 2]])
    }

    func testWidePagesStandAlone() {
        XCTAssertEqual(PagePairing.pairs(pages: 5, sizes: [1: wide], rtl: false, firstAlone: false), [[0], [1], [2, 3], [4]])
        XCTAssertEqual(PagePairing.pairs(pages: 4, sizes: [0: CGSize(width: 700, height: 1000), 2: wide], rtl: false, firstAlone: false), [[0, 1], [2], [3]])
    }

    func testShiftByOne() {
        XCTAssertEqual(PagePairing.pairs(pages: 5, sizes: [:], rtl: false, firstAlone: true), [[0], [1, 2], [3, 4]])
        XCTAssertEqual(PagePairing.pairs(pages: 0, sizes: [:], rtl: false, firstAlone: true), [])
    }
}
