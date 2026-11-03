import XCTest
@testable import Ahoge

final class BackupScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testOffIsNeverDue() {
        XCTAssertFalse(BackupSchedule.isDue(last: nil, intervalHours: 0, now: now))
    }

    func testNeverBackedUpIsDue() {
        XCTAssertTrue(BackupSchedule.isDue(last: nil, intervalHours: 24, now: now))
    }

    func testDueOnceTheIntervalHasPassed() {
        let sixHours = 6.0 * 3600
        XCTAssertFalse(BackupSchedule.isDue(last: now.addingTimeInterval(-sixHours + 1), intervalHours: 6, now: now))
        XCTAssertTrue(BackupSchedule.isDue(last: now.addingTimeInterval(-sixHours), intervalHours: 6, now: now))
        XCTAssertTrue(BackupSchedule.isDue(last: now.addingTimeInterval(-sixHours - 1), intervalHours: 6, now: now))
    }

    func testRotateDeletesTheOldestBeyondKeep() {
        let files = [
            (name: "b.ahbk", date: Date(timeIntervalSince1970: 200)),
            (name: "d.ahbk", date: Date(timeIntervalSince1970: 400)),
            (name: "a.ahbk", date: Date(timeIntervalSince1970: 100)),
            (name: "c.ahbk", date: Date(timeIntervalSince1970: 300)),
        ]
        XCTAssertEqual(BackupSchedule.rotate(files: files, keep: 2).sorted(), ["a.ahbk", "b.ahbk"])
        XCTAssertEqual(BackupSchedule.rotate(files: files, keep: 4), [])
        XCTAssertEqual(BackupSchedule.rotate(files: files, keep: 10), [])
    }

    func testRotateAlwaysKeepsTheNewest() {
        let files = [(name: "a.ahbk", date: Date(timeIntervalSince1970: 100)), (name: "b.ahbk", date: Date(timeIntervalSince1970: 200))]
        XCTAssertEqual(BackupSchedule.rotate(files: files, keep: 0), ["a.ahbk"])
    }
}
