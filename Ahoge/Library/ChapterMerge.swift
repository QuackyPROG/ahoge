import Foundation

struct ChapterState: Equatable {
    let url: String
    var name: String
    var number: Double
    var date: Date?
    var scanlator: String?
    var read: Bool
    var lastPageRead: Int
    var sourceOrder: Int
    /// When this chapter was first seen (Mihon's date_fetch); nil for a manga's first list.
    var dateFetch: Date? = nil
}

/// Combines a fresh chapter list with stored read state (matched by URL).
enum ChapterMerge {
    static func merge(existing: [ChapterState], fetched: [SourceChapter], now: Date = Date()) -> [ChapterState] {
        let byURL = Dictionary(existing.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var result: [ChapterState] = []
        for chapter in fetched where seen.insert(chapter.url).inserted {
            let old = byURL[chapter.url]
            // A manga's first chapter list is not news, and chapters stored before this field
            // existed keep nil, so neither floods Updates.
            let dateFetch: Date? = if let old { old.dateFetch } else if existing.isEmpty { nil } else { now }
            result.append(ChapterState(
                url: chapter.url,
                name: chapter.name,
                number: chapter.number,
                date: chapter.date.map { Date(timeIntervalSince1970: $0 / 1000) },
                scanlator: chapter.scanlator,
                read: old?.read ?? false,
                lastPageRead: old?.lastPageRead ?? 0,
                sourceOrder: result.count,
                dateFetch: dateFetch
            ))
        }
        return result
    }
}
