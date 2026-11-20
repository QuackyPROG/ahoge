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
        let carriedFrom = Dictionary(carries(existing: existing, fetched: fetched).map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var result: [ChapterState] = []
        for chapter in fetched where seen.insert(chapter.url).inserted {
            let old = byURL[chapter.url] ?? carriedFrom[chapter.url].flatMap { byURL[$0] }
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

    /// Chapters whose URL changed (a source moved domain or URL format): removed URL → added URL.
    /// They pair by equal chapter number (≥ 0), then by scanlator when a number has several; still ambiguous, they don't pair.
    static func carries(existing: [ChapterState], fetched: [SourceChapter]) -> [String: String] {
        let fetchedURLs = Set(fetched.map(\.url))
        let existingURLs = Set(existing.map(\.url))
        let removed = Dictionary(grouping: existing.filter { $0.number >= 0 && !fetchedURLs.contains($0.url) }, by: \.number)
        var seen = Set<String>()
        let added = Dictionary(grouping: fetched.filter { $0.number >= 0 && !existingURLs.contains($0.url) && seen.insert($0.url).inserted }, by: \.number)
        var pairs: [String: String] = [:]
        for (number, gone) in removed {
            guard let new = added[number] else { continue }
            if gone.count == 1, new.count == 1 {
                pairs[gone[0].url] = new[0].url
                continue
            }
            let newByScanlator = Dictionary(grouping: new, by: \.scanlator)
            for (scanlator, old) in Dictionary(grouping: gone, by: \.scanlator) {
                if old.count == 1, let match = newByScanlator[scanlator], match.count == 1 { pairs[old[0].url] = match[0].url }
            }
        }
        return pairs
    }
}
