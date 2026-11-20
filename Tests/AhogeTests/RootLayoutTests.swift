import UIKit
import XCTest
@testable import Ahoge

final class RootLayoutTests: XCTestCase {
    func testAnIPadGetsTheSplitViewAndAPhoneGetsTabs() {
        XCTAssertEqual(RootLayout.forIdiom(.pad), .split)
        XCTAssertEqual(RootLayout.forIdiom(.phone), .tabs)
    }
}
