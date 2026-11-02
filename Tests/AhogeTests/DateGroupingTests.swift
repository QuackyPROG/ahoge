import XCTest
@testable import Ahoge

final class DateGroupingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testGroupsByDayWithRelativeTitles() {
        let now = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13 UTC
        let dates = [
            now,
            now.addingTimeInterval(-3_600),
            now.addingTimeInterval(-86_400),
            now.addingTimeInterval(-3 * 86_400),
            now.addingTimeInterval(-30 * 86_400),
        ]
        let groups = DateGrouping.group(dates, by: { $0 }, now: now, calendar: calendar)
        XCTAssertEqual(groups.count, 4)
        XCTAssertEqual(groups.prefix(3).map(\.title), ["Today", "Yesterday", "3 days ago"])
        XCTAssertEqual(groups.map(\.items.count), [2, 1, 1, 1])
    }

    func testEmpty() {
        XCTAssertTrue(DateGrouping.group([Date](), by: { $0 }).isEmpty)
    }
}
