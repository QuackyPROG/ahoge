import XCTest
@testable import Ahoge

final class Base64Latin1Tests: XCTestCase {
    func testRoundTripLatin1() throws {
        XCTAssertEqual(try Base64Latin1.btoa("hi é"), "aGkg6Q==")
        XCTAssertEqual(try Base64Latin1.atob("aGkg6Q=="), "hi é")
    }

    func testForgivingDecode() throws {
        XCTAssertEqual(try Base64Latin1.atob(" aG\nkg6Q "), "hi é")
        XCTAssertEqual(try Base64Latin1.atob("aGk"), "hi")
        XCTAssertThrowsError(try Base64Latin1.atob("a"))
        XCTAssertThrowsError(try Base64Latin1.atob("a$=="))
    }

    func testBtoaRejectsWideCharacters() {
        XCTAssertThrowsError(try Base64Latin1.btoa("日本"))
    }
}
