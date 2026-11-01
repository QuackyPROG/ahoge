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
}

/// Combines a fresh chapter list with stored read state (matched by URL).
enum ChapterMerge {
    static func merge(existing: [ChapterState], fetched: [SourceChapter]) -> [ChapterState] {
        let byURL = Dictionary(existing.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var result: [ChapterState] = []
        for chapter in fetched where seen.insert(chapter.url).inserted {
            let old = byURL[chapter.url]
            result.append(ChapterState(
                url: chapter.url,
                name: chapter.name,
                number: chapter.number,
                date: chapter.date.map { Date(timeIntervalSince1970: $0 / 1000) },
                scanlator: chapter.scanlator,
                read: old?.read ?? false,
                lastPageRead: old?.lastPageRead ?? 0,
                sourceOrder: result.count
            ))
        }
        return result
    }
}
