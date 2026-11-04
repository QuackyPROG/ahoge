import Foundation

/// Which chapters download automation adds or removes (Mihon's download settings). Pure, so the
/// rules are tested without a queue; `DownloadManager` applies the answers.
enum DownloadRules {
    /// Category `flags` bit 1: titles in this category are not auto-downloaded.
    static let excludedCategoryFlag = 1 << 1

    struct Settings: Equatable {
        var removeAfterMarkedRead = false
        /// 0 is off, 1 the chapter just read, 2–5 the 2nd–5th to last read.
        var removeAfterReading = 0
        var removeBookmarked = false
        var downloadAhead = 0
        var downloadNew = false

        static func current(_ defaults: UserDefaults = .standard) -> Settings {
            Settings(
                removeAfterMarkedRead: Pref.removeAfterMarkedRead.value(in: defaults),
                removeAfterReading: Pref.removeAfterReading.value(in: defaults),
                removeBookmarked: Pref.removeBookmarkedToo.value(in: defaults),
                downloadAhead: Pref.downloadAhead.value(in: defaults),
                downloadNew: Pref.downloadNewChapters.value(in: defaults)
            )
        }
    }

    /// Chapters marked read by hand that should lose their download. Bookmarked ones stay unless asked.
    static func chaptersToDelete(markedRead chapters: [ChapterRecord], prefs: Settings) -> [ChapterRecord] {
        guard prefs.removeAfterMarkedRead else { return [] }
        return chapters.filter { prefs.removeBookmarked || !$0.bookmark }
    }

    /// After `read` is finished in the reader: the chapter `removeAfterReading - 1` places before it
    /// in reading order (oldest first), if that one is read too.
    static func chaptersToDelete(after read: ChapterRecord, in chapters: [ChapterRecord], prefs: Settings) -> [ChapterRecord] {
        guard prefs.removeAfterReading > 0 else { return [] }
        let ordered = chapters.sorted { $0.sourceOrder > $1.sourceOrder }
        guard let index = ordered.firstIndex(where: { $0.key == read.key }) else { return [] }
        let target = index - (prefs.removeAfterReading - 1)
        guard ordered.indices.contains(target) else { return [] }
        let chapter = ordered[target]
        guard chapter.key == read.key || chapter.read else { return [] }
        return prefs.removeBookmarked || !chapter.bookmark ? [chapter] : []
    }

    /// Mihon's download ahead: for a library title whose open chapter and the next one are both
    /// downloaded, the `downloadAhead` unread chapters after the next one.
    static func chaptersToDownloadAhead(current: ChapterRecord, in chapters: [ChapterRecord], inLibrary: Bool, downloaded: Set<String>, prefs: Settings) -> [ChapterRecord] {
        guard prefs.downloadAhead > 0, inLibrary, downloaded.contains(current.key) else { return [] }
        // Newer chapters have a lower sourceOrder; the closest comes first.
        let newer = chapters.filter { $0.sourceOrder < current.sourceOrder }.sorted { $0.sourceOrder > $1.sourceOrder }
        guard let next = newer.first, downloaded.contains(next.key) else { return [] }
        return Array(newer.dropFirst().filter { !$0.read }.prefix(prefs.downloadAhead))
    }

    /// New chapters a library update found that should download: unread ones of a library title in
    /// no excluded category.
    static func chaptersToAutoDownload(new: [ChapterRecord], manga: LibraryManga, categories: [MangaCategory], prefs: Settings) -> [ChapterRecord] {
        guard prefs.downloadNew, manga.inLibrary,
              !categories.contains(where: { $0.flags & excludedCategoryFlag != 0 }) else { return [] }
        return new.filter { !$0.read }
    }
}
