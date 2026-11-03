import Foundation

/// A filter row's three states (Mihon's tri-state checkbox).
enum TriState: String, Codable, CaseIterable {
    case off, include, exclude

    /// The order a tap cycles through.
    var next: TriState {
        switch self {
        case .off: .include
        case .include: .exclude
        case .exclude: .off
        }
    }

    func matches(_ value: Bool) -> Bool {
        switch self {
        case .off: true
        case .include: value
        case .exclude: !value
        }
    }
}

struct LibraryFilters: Codable, Equatable {
    var downloaded = TriState.off
    var unread = TriState.off
    var started = TriState.off
    var bookmarked = TriState.off
    var completed = TriState.off
    /// Titles with their own update interval.
    var customInterval = TriState.off

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        downloaded = try values.decodeIfPresent(TriState.self, forKey: .downloaded) ?? .off
        unread = try values.decodeIfPresent(TriState.self, forKey: .unread) ?? .off
        started = try values.decodeIfPresent(TriState.self, forKey: .started) ?? .off
        bookmarked = try values.decodeIfPresent(TriState.self, forKey: .bookmarked) ?? .off
        completed = try values.decodeIfPresent(TriState.self, forKey: .completed) ?? .off
        customInterval = try values.decodeIfPresent(TriState.self, forKey: .customInterval) ?? .off
    }

    var isActive: Bool { self != LibraryFilters() }

    /// How it is stored in `Pref.libraryFilters`; empty when nothing is filtered.
    var stored: String {
        guard isActive, let data = try? JSONEncoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    init(stored: String) {
        if let decoded = try? JSONDecoder().decode(LibraryFilters.self, from: Data(stored.utf8)) { self = decoded } else { self.init() }
    }
}

enum LibrarySortKey: String, Codable, CaseIterable, Identifiable {
    case title, totalChapters, lastRead, lastUpdateCheck, unreadCount, latestChapter, chapterFetchDate, dateAdded, random

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: "Alphabetical"
        case .totalChapters: "Total chapters"
        case .lastRead: "Last read"
        case .lastUpdateCheck: "Last update check"
        case .unreadCount: "Unread count"
        case .latestChapter: "Latest chapter"
        case .chapterFetchDate: "Chapter fetch date"
        case .dateAdded: "Date added"
        case .random: "Random"
        }
    }
}

struct LibrarySort: Codable, Equatable {
    var key: LibrarySortKey
    var ascending: Bool

    init(key: LibrarySortKey, ascending: Bool) {
        self.key = key
        self.ascending = ascending
    }

    /// "title:asc". This is what `Pref.librarySort` and a category's `sortMode` hold.
    var stored: String { key.rawValue + (ascending ? ":asc" : ":desc") }

    /// Reads `stored`, and the plain labels earlier versions kept in `Pref.librarySort`.
    init?(stored: String) {
        let parts = stored.split(separator: ":").map(String.init)
        if parts.count == 2, let key = LibrarySortKey(rawValue: parts[0]), parts[1] == "asc" || parts[1] == "desc" {
            self.init(key: key, ascending: parts[1] == "asc")
            return
        }
        switch stored {
        case "Title": self.init(key: .title, ascending: true)
        case "Date added": self.init(key: .dateAdded, ascending: false)
        case "Last read": self.init(key: .lastRead, ascending: false)
        case "Unread count": self.init(key: .unreadCount, ascending: false)
        default: return nil
        }
    }

    /// The sort a tap on `tapped` leads to: the same key flips direction, another key starts ascending.
    func tapping(_ tapped: LibrarySortKey) -> LibrarySort {
        tapped == key ? LibrarySort(key: key, ascending: !ascending) : LibrarySort(key: tapped, ascending: true)
    }
}

extension LibrarySort {
    static let `default` = LibrarySort(key: .title, ascending: true)

    /// The sort a shelf shows. With per-category sort on, a shelf's own sort wins over `global`
    /// (the stored global sort); shelf 0 is Default, whose sort lives in `defaultShelf`.
    static func effective(global: String, perCategory: Bool, shelfId: Int, defaultShelf: String, categories: [MangaCategory]) -> LibrarySort {
        let fallback = LibrarySort(stored: global) ?? .default
        guard perCategory else { return fallback }
        let own = shelfId == 0 ? defaultShelf : categories.first { Int($0.id) == shelfId }?.sortMode
        return own.flatMap { LibrarySort(stored: $0) } ?? fallback
    }
}

/// What the query needs to know beyond the titles themselves: downloads live in `DownloadManager`.
struct LibraryFacts {
    var downloadedCount: (String) -> Int = { _ in 0 }
    /// Bookmarks are also counted from the chapters loaded with the title; this adds nothing by default.
    var bookmarkedCount: (String) -> Int = { _ in 0 }
    /// Fixed for a session, so random order does not reshuffle on every redraw.
    var randomSeed: UInt64 = 0
}

/// Search, filters and sort of the Library, as plain data in and out.
struct LibraryQuery: Codable, Equatable {
    var search = ""
    var filters = LibraryFilters()
    var sort = LibrarySort(key: .title, ascending: true)

    func apply(to manga: [LibraryManga], facts: LibraryFacts) -> [LibraryManga] {
        let kept = manga.filter { matchesSearch($0) && passesFilters($0, facts) }
        return kept.sorted { precedes($0, $1, facts) }
    }

    // MARK: Search

    /// Matches title, author, artist and genres; `genre:action` looks at genres only.
    private func matchesSearch(_ manga: LibraryManga) -> Bool {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return true }
        let prefix = "genre:"
        if term.lowercased().hasPrefix(prefix) {
            let genre = term.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            return genre.isEmpty || manga.genres.contains { $0.localizedCaseInsensitiveContains(genre) }
        }
        return manga.title.localizedCaseInsensitiveContains(term)
            || manga.author.localizedCaseInsensitiveContains(term)
            || manga.artist.localizedCaseInsensitiveContains(term)
            || manga.genres.contains { $0.localizedCaseInsensitiveContains(term) }
    }

    // MARK: Filters

    private func passesFilters(_ manga: LibraryManga, _ facts: LibraryFacts) -> Bool {
        filters.downloaded.matches(facts.downloadedCount(manga.key) > 0)
            && filters.unread.matches(manga.unreadCount > 0)
            && filters.started.matches(manga.chapters.contains { $0.read || $0.lastPageRead > 0 })
            && filters.bookmarked.matches(bookmarked(manga, facts) > 0)
            && filters.completed.matches(manga.status == "completed")
            && filters.customInterval.matches(manga.updateInterval != nil)
    }

    private func bookmarked(_ manga: LibraryManga, _ facts: LibraryFacts) -> Int {
        max(facts.bookmarkedCount(manga.key), manga.chapters.filter(\.bookmark).count)
    }

    // MARK: Sort

    private func precedes(_ a: LibraryManga, _ b: LibraryManga, _ facts: LibraryFacts) -> Bool {
        var order = 0
        switch sort.key {
        case .title: order = titleOrder(a, b)
        case .totalChapters: order = Self.cmp(a.chapters.count, b.chapters.count)
        case .lastRead: order = Self.cmp(a.lastReadAt ?? .distantPast, b.lastReadAt ?? .distantPast)
        case .lastUpdateCheck: order = Self.cmp(a.lastChapterFetch ?? .distantPast, b.lastChapterFetch ?? .distantPast)
        case .unreadCount: order = Self.cmp(a.unreadCount, b.unreadCount)
        case .latestChapter: order = Self.cmp(Self.latestUpload(a), Self.latestUpload(b))
        case .chapterFetchDate: order = Self.cmp(Self.latestFetch(a), Self.latestFetch(b))
        case .dateAdded: order = Self.cmp(a.dateAdded ?? .distantPast, b.dateAdded ?? .distantPast)
        case .random:
            // Direction means nothing for a shuffle.
            let rank = Self.cmp(Self.shuffleRank(a.key, seed: facts.randomSeed), Self.shuffleRank(b.key, seed: facts.randomSeed))
            return rank != 0 ? rank < 0 : a.key < b.key
        }
        if order != 0 { return sort.ascending ? order < 0 : order > 0 }
        // Ties read alphabetically whatever the direction.
        let tie = titleOrder(a, b)
        return tie != 0 ? tie < 0 : a.key < b.key
    }

    private func titleOrder(_ a: LibraryManga, _ b: LibraryManga) -> Int {
        switch a.title.localizedCaseInsensitiveCompare(b.title) {
        case .orderedAscending: -1
        case .orderedDescending: 1
        case .orderedSame: 0
        }
    }

    private static func cmp<T: Comparable>(_ x: T, _ y: T) -> Int { x < y ? -1 : x > y ? 1 : 0 }

    private static func latestUpload(_ manga: LibraryManga) -> Date {
        manga.chapters.compactMap(\.dateUpload).max() ?? .distantPast
    }

    private static func latestFetch(_ manga: LibraryManga) -> Date {
        manga.chapters.compactMap(\.dateFetch).max() ?? .distantPast
    }

    /// FNV-1a of the key mixed with the seed, then splitmix64's finaliser: a stable pseudo-random rank.
    private static func shuffleRank(_ key: String, seed: UInt64) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037 ^ seed
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        hash ^= hash >> 30
        hash = hash &* 0xbf58_476d_1ce4_e5b9
        hash ^= hash >> 27
        hash = hash &* 0x94d0_49bb_1331_11eb
        hash ^= hash >> 31
        return hash
    }
}
