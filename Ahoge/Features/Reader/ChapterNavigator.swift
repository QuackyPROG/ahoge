import Foundation

/// Mihon's "Reading" rules for which chapter comes next.
struct SkipRules: Equatable {
    var skipRead = false
    /// Skips chapters the chapter list filters out, and excluded scanlators.
    var skipFiltered = true
    /// Skips chapters with the number just read (several groups translating the same chapter).
    var skipDuplicates = false

    static func current(_ defaults: UserDefaults = .standard) -> SkipRules {
        SkipRules(
            skipRead: Pref.readerSkipRead.value(in: defaults),
            skipFiltered: Pref.readerSkipFiltered.value(in: defaults),
            skipDuplicates: Pref.readerSkipDuplicates.value(in: defaults)
        )
    }
}

/// The chapter before and after another in reading order: the chapter list's sort, oldest first.
struct ChapterNavigator {
    /// Reading order.
    private let order: [ChapterRecord]
    private let display: ChapterDisplay
    private let excludedScanlators: Set<String>
    private let rules: SkipRules

    init(chapters: [ChapterRecord], display: ChapterDisplay, excludedScanlators: Set<String>, rules: SkipRules) {
        var reading = display
        reading.ascending = true
        reading.filter = .all
        order = reading.apply(to: chapters)
        self.display = display
        self.excludedScanlators = excludedScanlators
        self.rules = rules
    }

    func next(after chapter: ChapterRecord) -> ChapterRecord? {
        guard let index = order.firstIndex(where: { $0.key == chapter.key }) else { return nil }
        return pick(Array(order[(index + 1)...]), from: chapter)
    }

    func previous(before chapter: ChapterRecord) -> ChapterRecord? {
        guard let index = order.firstIndex(where: { $0.key == chapter.key }) else { return nil }
        return pick(Array(order[..<index].reversed()), from: chapter)
    }

    private func allowed(_ chapter: ChapterRecord) -> Bool {
        if rules.skipRead, chapter.read { return false }
        if rules.skipFiltered {
            switch display.filter {
            case .all: break
            case .unread: if chapter.read { return false }
            case .read: if !chapter.read { return false }
            }
            if let scanlator = chapter.scanlator, excludedScanlators.contains(scanlator) { return false }
        }
        return true
    }

    /// The first allowed chapter of `candidates` (nearest first). With duplicates skipped, the first
    /// with another number, preferring `current`'s scanlator, then the first in source order.
    private func pick(_ candidates: [ChapterRecord], from current: ChapterRecord) -> ChapterRecord? {
        let eligible = candidates.filter(allowed)
        // Unknown numbers (below 0) are never duplicates.
        guard rules.skipDuplicates, current.number >= 0 else { return eligible.first }
        guard let target = eligible.first(where: { $0.number != current.number }) else { return nil }
        guard target.number >= 0 else { return target }
        let same = eligible.filter { $0.number == target.number }
        return same.first { $0.scanlator == current.scanlator } ?? same.min { $0.sourceOrder < $1.sourceOrder }
    }
}
