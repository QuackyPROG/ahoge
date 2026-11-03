import Foundation

/// How a manga's chapter list is sorted and filtered. Saved per manga in UserDefaults, so the
/// library schema does not change for a view preference.
struct ChapterDisplay: Codable, Equatable {
    enum Sort: String, Codable, CaseIterable, Identifiable {
        case source, number, date
        var id: String { rawValue }
        var title: String {
            switch self {
            case .source: "By source"
            case .number: "By chapter number"
            case .date: "By upload date"
            }
        }
    }

    enum Filter: String, Codable, CaseIterable, Identifiable {
        case all, unread, read
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "All chapters"
            case .unread: "Unread"
            case .read: "Read"
            }
        }
    }

    var sort: Sort = .source
    /// false: newest first (the source's order), true: oldest first.
    var ascending = false
    var filter: Filter = .all
    /// Bookmarked chapters only (include) or none of them (exclude).
    var bookmarked = TriState.off
    /// Rows say "Chapter N" instead of the source's chapter name (Mihon's display mode).
    var numberTitles = false

    var isDefault: Bool { self == ChapterDisplay() }

    /// `excluding` are scanlators the reader hid for this manga; their chapters are left out.
    func apply(to chapters: [ChapterRecord], excluding scanlators: Set<String> = []) -> [ChapterRecord] {
        let kept = chapters.filter { chapter in
            if let scanlator = chapter.scanlator, scanlators.contains(scanlator) { return false }
            guard bookmarked.matches(chapter.bookmark) else { return false }
            switch filter {
            case .all: return true
            case .unread: return !chapter.read
            case .read: return chapter.read
            }
        }
        // Each order is "newest first"; ties fall back to the source order.
        let newestFirst = kept.sorted { a, b in
            switch sort {
            case .source:
                return a.sourceOrder < b.sourceOrder
            case .number:
                if a.number != b.number { return a.number > b.number }
            case .date:
                let da = a.dateUpload ?? .distantPast, db = b.dateUpload ?? .distantPast
                if da != db { return da > db }
            }
            return a.sourceOrder < b.sourceOrder
        }
        return ascending ? newestFirst.reversed() : newestFirst
    }

    /// What a row is called: the source's name, or "Chapter N" when the number is known.
    func title(of chapter: ChapterRecord) -> String {
        guard numberTitles, chapter.number >= 0 else { return chapter.name }
        return "Chapter \(chapter.number.formatted())"
    }

    private static func defaultsKey(_ mangaKey: String) -> String { "chapterDisplay." + mangaKey }

    /// The display a manga without its own uses: the one saved with "Set as default", else the built-in.
    static func globalDefault(from defaults: UserDefaults = .standard) -> ChapterDisplay {
        let stored = Pref.chapterDisplayDefault.value(in: defaults)
        return (try? JSONDecoder().decode(ChapterDisplay.self, from: Data(stored.utf8))) ?? ChapterDisplay()
    }

    /// "Set as default". With `clearing`, those manga lose their own display and follow the default.
    func saveAsDefault(clearing mangaKeys: [String] = [], to defaults: UserDefaults = .standard) {
        if self == ChapterDisplay() {
            Pref.chapterDisplayDefault.set("", in: defaults)
        } else if let data = try? JSONEncoder().encode(self) {
            Pref.chapterDisplayDefault.set(String(decoding: data, as: UTF8.self), in: defaults)
        }
        for key in mangaKeys { defaults.removeObject(forKey: Self.defaultsKey(key)) }
    }

    static func load(for mangaKey: String, from defaults: UserDefaults = .standard) -> ChapterDisplay {
        guard let data = defaults.data(forKey: defaultsKey(mangaKey)),
              let value = try? JSONDecoder().decode(ChapterDisplay.self, from: data) else { return globalDefault(from: defaults) }
        return value
    }

    func save(for mangaKey: String, to defaults: UserDefaults = .standard) {
        if self == Self.globalDefault(from: defaults) {
            defaults.removeObject(forKey: Self.defaultsKey(mangaKey))
        } else if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey(mangaKey))
        }
    }
}

extension ChapterDisplay {
    /// Older saved displays lack the newer keys.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sort = try values.decodeIfPresent(Sort.self, forKey: .sort) ?? .source
        ascending = try values.decodeIfPresent(Bool.self, forKey: .ascending) ?? false
        filter = try values.decodeIfPresent(Filter.self, forKey: .filter) ?? .all
        bookmarked = try values.decodeIfPresent(TriState.self, forKey: .bookmarked) ?? .off
        numberTitles = try values.decodeIfPresent(Bool.self, forKey: .numberTitles) ?? false
    }
}

/// Chapters the list is missing, from the numbers of two neighbours (Mihon's chapter gap).
enum ChapterGaps {
    /// Whole chapters missing between two numbers; 0 when either is unknown (below 0) or they are consecutive.
    static func missing(between a: Double, and b: Double) -> Int {
        guard a >= 0, b >= 0 else { return 0 }
        return max(0, Int((abs(a - b)).rounded(.down)) - 1)
    }
}
