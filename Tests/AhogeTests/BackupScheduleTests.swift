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

    func testAutomaticNamesAreToldApart() {
        XCTAssertTrue(BackupFile.isAutomatic("ahoge_auto_2026-11-20_10-00.ahbk"))
        XCTAssertFalse(BackupFile.isAutomatic("ahoge_2026-11-20_10-00.ahbk"))
        XCTAssertFalse(BackupFile.isAutomatic("notes.ahbk"))
    }

    func testAutomaticNameCarriesThePrefix() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 1_795_168_800) // 2026-11-20 10:00 UTC
        XCTAssertEqual(BackupFile.name(at: date, calendar: calendar, automatic: true), "ahoge_auto_2026-11-20_10-00.ahbk")
        XCTAssertEqual(BackupFile.name(at: date, calendar: calendar), "ahoge_2026-11-20_10-00.ahbk")
    }
}
