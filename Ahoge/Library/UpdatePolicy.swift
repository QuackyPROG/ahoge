import Foundation

/// Why a library update leaves a title out.
enum SkipReason: Equatable {
    case hasUnread, notStarted, completed, notDue, excludedCategory
}

/// The settings that decide which titles a library update refreshes.
struct UpdateRules: Equatable {
    /// Category flag bit 0: the category is left out of library updates.
    static let excludedCategoryFlag = 1

    var skipUnread = false
    var skipUnstarted = false
    var skipCompleted = true
    /// Titles are refreshed when their predicted next release is near, not on every update.
    var smartUpdate = true
    var excludedCategories: Set<Int64> = []

    static func current(defaults: UserDefaults = .standard, categories: [MangaCategory]) -> UpdateRules {
        UpdateRules(
            skipUnread: Pref.updateSkipUnread.value(in: defaults),
            skipUnstarted: Pref.updateSkipUnstarted.value(in: defaults),
            skipCompleted: Pref.updateSkipCompleted.value(in: defaults),
            smartUpdate: Pref.updateSmart.value(in: defaults),
            excludedCategories: Set(categories.filter { $0.flags & excludedCategoryFlag != 0 }.map(\.id))
        )
    }
}

enum UpdatePolicy {
    /// The first rule that keeps `manga` out of an update, or nil when it should be refreshed.
    static func decide(_ manga: LibraryManga, categories: Set<Int64>, rules: UpdateRules, now: Date) -> SkipReason? {
        if !categories.isDisjoint(with: rules.excludedCategories) { return .excludedCategory }
        if rules.skipCompleted, manga.status == "completed" { return .completed }
        if rules.skipUnread, manga.unreadCount > 0 { return .hasUnread }
        // A title that was never fetched has no chapters to have started.
        if rules.skipUnstarted, !manga.chapters.isEmpty, !manga.hasStartedReading { return .notStarted }
        if manga.updateInterval == 0 { return .notDue }
        if let due = dueDate(manga, rules: rules), now < due { return .notDue }
        return nil
    }

    /// When the title is next due: its own interval after the last fetch, else the predicted date
    /// while smart update is on. Nil means due whenever an update runs (or never, for interval 0).
    static func dueDate(_ manga: LibraryManga, rules: UpdateRules) -> Date? {
        if let days = manga.updateInterval {
            guard days > 0, let last = manga.lastChapterFetch else { return nil }
            return ReleasePredictor.nextUpdate(lastFetch: last, interval: Double(days) * 86_400)
        }
        return rules.smartUpdate ? manga.nextUpdate : nil
    }
}

/// Guesses how often a series releases from the dates its chapters were uploaded.
enum ReleasePredictor {
    static let minimum: TimeInterval = 86_400
    static let maximum: TimeInterval = 28 * 86_400
    /// How many of the latest gaps between chapters count.
    static let sampleSize = 10

    /// The median gap of the latest chapters, clamped to 1–28 days; nil with fewer than 3 dates.
    static func interval(uploadDates: [Date]) -> TimeInterval? {
        guard uploadDates.count >= 3 else { return nil }
        let recent = Array(uploadDates.sorted().suffix(sampleSize + 1))
        let gaps = zip(recent.dropFirst(), recent).map { $0.timeIntervalSince($1) }.sorted()
        let middle = gaps.count / 2
        let median = gaps.count % 2 == 1 ? gaps[middle] : (gaps[middle - 1] + gaps[middle]) / 2
        return min(max(median, minimum), maximum)
    }

    static func nextUpdate(lastFetch: Date, interval: TimeInterval) -> Date {
        lastFetch.addingTimeInterval(interval)
    }

    /// The title's own interval (nil for "never"), else the prediction from its chapters.
    static func interval(for manga: LibraryManga) -> TimeInterval? {
        if let days = manga.updateInterval { return days > 0 ? Double(days) * 86_400 : nil }
        return interval(uploadDates: manga.chapters.compactMap(\.dateUpload))
    }

    static func nextUpdate(for manga: LibraryManga, lastFetch: Date) -> Date? {
        interval(for: manga).map { nextUpdate(lastFetch: lastFetch, interval: $0) }
    }
}
