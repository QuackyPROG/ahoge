import XCTest
@testable import Ahoge

final class DateFormattingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private let locale = Locale(identifier: "en_US")
    // 2026-11-10 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_794_312_000)

    private func text(daysAgo: Int, format: String = DateFormatting.system, relative: Bool) -> String {
        DateFormatting.string(for: now.addingTimeInterval(-Double(daysAgo) * 86_400), format: format, relative: relative, now: now, calendar: calendar, locale: locale)
    }

    func testSystemFormatIsAbbreviated() {
        XCTAssertEqual(text(daysAgo: 7, relative: false), "Nov 3, 2026")
    }

    func testCustomPatterns() {
        XCTAssertEqual(text(daysAgo: 7, format: "yyyy-MM-dd", relative: false), "2026-11-03")
        XCTAssertEqual(text(daysAgo: 7, format: "dd/MM/yy", relative: false), "03/11/26")
        XCTAssertEqual(text(daysAgo: 7, format: "MMM dd, yyyy", relative: false), "Nov 03, 2026")
    }

    func testRelativeCoversTheLastWeek() {
        XCTAssertEqual(text(daysAgo: 0, relative: true), "Today")
        XCTAssertEqual(text(daysAgo: 1, relative: true), "Yesterday")
        XCTAssertEqual(text(daysAgo: 3, relative: true), "3 days ago")
        XCTAssertEqual(text(daysAgo: 6, relative: true), "6 days ago")
    }

    func testRelativeFallsBackToTheChosenFormatAfterAWeek() {
        XCTAssertEqual(text(daysAgo: 7, format: "yyyy-MM-dd", relative: true), "2026-11-03")
    }

    func testRelativeOffShowsTheDateEvenForToday() {
        XCTAssertEqual(text(daysAgo: 0, format: "yyyy-MM-dd", relative: false), "2026-11-10")
    }
}
