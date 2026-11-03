import Foundation

/// Mihon's Statistics screen, computed from what the library already holds.
enum LibraryStatistics {
    struct Stats: Equatable {
        var titles = 0
        var completed = 0
        /// Titles with at least one chapter read or begun.
        var started = 0
        var local = 0
        var chaptersTotal = 0
        var chaptersRead = 0
        var chaptersDownloaded = 0
        /// Seconds spent reading chapters of these titles.
        var readSeconds = 0
        /// Distinct sources the titles come from.
        var sources = 0
    }

    /// - Parameters:
    ///   - history: seconds read, by chapter key.
    ///   - downloaded: downloaded chapter count, by manga key.
    static func compute(manga: [LibraryManga], history: [String: Int], downloaded: [String: Int]) -> Stats {
        var stats = Stats()
        var sources = Set<String>()
        for title in manga {
            stats.titles += 1
            if title.status == "completed" { stats.completed += 1 }
            if title.chapters.contains(where: { $0.read || $0.lastPageRead > 0 }) { stats.started += 1 }
            if title.sourceId == LibraryBadges.localSourceId { stats.local += 1 }
            sources.insert(title.sourceId)
            stats.chaptersTotal += title.chapters.count
            stats.chaptersRead += title.chapters.filter(\.read).count
            stats.chaptersDownloaded += downloaded[title.key] ?? 0
            stats.readSeconds += title.chapters.reduce(0) { $0 + (history[$1.key] ?? 0) }
        }
        stats.sources = sources.count
        return stats
    }

    /// "1 h 5 min", "12 min" or "0 min".
    static func duration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes >= 60 { return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min" }
        return "\(minutes) min"
    }
}
