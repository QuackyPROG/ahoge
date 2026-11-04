import XCTest
@testable import Ahoge

final class SigningInfoTests: XCTestCase {
    private func profile(_ entries: String) -> Data {
        var data = Data([0x30, 0x82, 0x3C, 0x00])
        data.append(Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>\(entries)</dict></plist>
        """.utf8))
        data.append(Data([0xA0, 0x82, 0x00, 0xFF]))
        return data
    }

    func testExpiryIsReadFromInsideTheSignature() {
        let data = profile("<key>ExpirationDate</key><date>2026-11-11T12:00:00Z</date>")
        XCTAssertEqual(SigningInfo.expiry(inProfile: data), Date(timeIntervalSince1970: 1_794_398_400))
    }

    func testProfileWithoutAnExpiryHasNone() {
        XCTAssertNil(SigningInfo.expiry(inProfile: profile("<key>Name</key><string>Ahoge</string>")))
    }

    func testBytesWithoutAPlistHaveNoExpiry() {
        XCTAssertNil(SigningInfo.expiry(inProfile: Data([0x30, 0x82, 0x00])))
    }

    func testExpiresSoonUnderTwoDays() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(SigningInfo.expiresSoon(now.addingTimeInterval(47 * 60 * 60), now: now))
        XCTAssertFalse(SigningInfo.expiresSoon(now.addingTimeInterval(49 * 60 * 60), now: now))
    }
}
