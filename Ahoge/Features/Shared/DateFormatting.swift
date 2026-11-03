import Foundation

/// How chapter dates are written, from the Appearance settings.
enum DateFormatting {
    static let system = "system"
    /// The patterns offered besides the system's own.
    static let presets: [(pattern: String, title: String)] = [
        ("MM/dd/yy", "MM/dd/yy"),
        ("dd/MM/yy", "dd/MM/yy"),
        ("yyyy-MM-dd", "yyyy-MM-dd"),
        ("dd MMM yyyy", "dd MMM yyyy"),
        ("MMM dd, yyyy", "MMM dd, yyyy"),
    ]

    /// With `relative`, the last week reads "Today", "Yesterday" or "N days ago" (like the Updates headers);
    /// older dates and everything else follow `format`.
    static func string(
        for date: Date, format: String, relative: Bool,
        now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        if relative {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
            if days < 7 { return DateGrouping.title(for: calendar.startOfDay(for: date), now: now, calendar: calendar) }
        }
        if format == system {
            return date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// With the stored settings.
    static func string(for date: Date) -> String {
        string(for: date, format: Pref.dateFormat.value(), relative: Pref.relativeTimestamps.value())
    }
}
