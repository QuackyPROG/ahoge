import XCTest
@testable import Ahoge

final class LockPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testColdLaunchAlwaysAsks() {
        XCTAssertTrue(LockPolicy.needsUnlock(lastActive: nil, now: now, setting: -1))
        XCTAssertTrue(LockPolicy.needsUnlock(lastActive: nil, now: now, setting: 5))
    }

    func testAlwaysAsksEvenForAQuickReturn() {
        XCTAssertTrue(LockPolicy.needsUnlock(lastActive: now.addingTimeInterval(-1), now: now, setting: 0))
    }

    func testWaitsForTheConfiguredMinutes() {
        XCTAssertFalse(LockPolicy.needsUnlock(lastActive: now.addingTimeInterval(-119), now: now, setting: 2))
        XCTAssertTrue(LockPolicy.needsUnlock(lastActive: now.addingTimeInterval(-120), now: now, setting: 2))
    }

    func testNeverDoesNotRelockAfterTheFirstUnlock() {
        XCTAssertFalse(LockPolicy.needsUnlock(lastActive: now.addingTimeInterval(-86_400), now: now, setting: -1))
    }
}
