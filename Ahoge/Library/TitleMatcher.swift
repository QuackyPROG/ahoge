import Foundation

/// Finds library entries that are probably the same series as a title (Mihon's "possible duplicates").
enum TitleMatcher {
    /// Library entries whose normalised title shares at least 80% of its words with `title`, or
    /// where one title contains the other as whole words.
    static func similar(_ title: String, to library: [LibraryManga]) -> [LibraryManga] {
        let words = normalised(title)
        guard !words.isEmpty else { return [] }
        return library.filter { matches(words, normalised($0.title)) }
    }

    /// Lowercased words without accents, punctuation, a leading "the", or season and part markers.
    static func normalised(_ title: String) -> [String] {
        var text = title.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
        // "Season 2", "2nd Season", "S2", "Part 3", "Cour 2" mark the same series.
        for pattern in [#"\b(season|part|cour)\s*\d+\b"#, #"\b\d+(st|nd|rd|th)\s+(season|part|cour)\b"#, #"\bs\d+\b"#] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return words.first == "the" ? Array(words.dropFirst()) : words
    }

    private static func matches(_ a: [String], _ b: [String]) -> Bool {
        guard !b.isEmpty else { return false }
        if a == b { return true }
        let setA = Set(a)
        let setB = Set(b)
        let jaccard = Double(setA.intersection(setB).count) / Double(setA.union(setB).count)
        if jaccard >= 0.8 { return true }
        let (short, long) = a.count <= b.count ? (a, b) : (b, a)
        // One word in common ("one") is too weak to call a duplicate.
        return short.joined().count >= 4 && contains(long, short)
    }

    /// Whether `words` holds `part` as consecutive words.
    private static func contains(_ words: [String], _ part: [String]) -> Bool {
        guard part.count <= words.count else { return false }
        return (0...(words.count - part.count)).contains { Array(words[$0..<($0 + part.count)]) == part }
    }
}
