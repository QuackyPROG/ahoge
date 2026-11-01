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

    var isDefault: Bool { self == ChapterDisplay() }

    func apply(to chapters: [ChapterRecord]) -> [ChapterRecord] {
        let kept = chapters.filter { chapter in
            switch filter {
            case .all: true
            case .unread: !chapter.read
            case .read: chapter.read
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

    private static func defaultsKey(_ mangaKey: String) -> String { "chapterDisplay." + mangaKey }

    static func load(for mangaKey: String, from defaults: UserDefaults = .standard) -> ChapterDisplay {
        guard let data = defaults.data(forKey: defaultsKey(mangaKey)),
              let value = try? JSONDecoder().decode(ChapterDisplay.self, from: data) else { return ChapterDisplay() }
        return value
    }

    func save(for mangaKey: String, to defaults: UserDefaults = .standard) {
        if isDefault {
            defaults.removeObject(forKey: Self.defaultsKey(mangaKey))
        } else if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey(mangaKey))
        }
    }
}
