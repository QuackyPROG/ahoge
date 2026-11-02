import Foundation

/// Items under one day header in Updates and History.
struct DateGroup<Item> {
    let day: Date
    let title: String
    var items: [Item]
}

enum DateGrouping {
    /// Groups items already sorted newest first by the day of `date`.
    static func group<Item>(_ items: [Item], by date: (Item) -> Date, now: Date = Date(), calendar: Calendar = .current) -> [DateGroup<Item>] {
        var groups: [DateGroup<Item>] = []
        for item in items {
            let day = calendar.startOfDay(for: date(item))
            if groups.last?.day == day {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append(DateGroup(day: day, title: title(for: day, now: now, calendar: calendar), items: [item]))
            }
        }
        return groups
    }

    /// Mihon's relative headers: Today, Yesterday, "N days ago" within a week, then the date.
    static func title(for day: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "Today" // 0, or negative from clock skew
        case 1: return "Yesterday"
        case 2..<7: return "\(days) days ago"
        default: return day.formatted(.dateTime.day().month(.abbreviated).year())
        }
    }
}
