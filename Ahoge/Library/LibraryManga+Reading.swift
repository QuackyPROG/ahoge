import Foundation

extension LibraryManga {
    /// Where "Resume" and the library's continue button open: the oldest unread chapter (chapters are
    /// newest first), else the newest.
    var nextChapter: ChapterRecord? {
        let list = sortedChapters
        guard !list.isEmpty else { return nil }
        return list.last { !$0.read } ?? list.first
    }

    /// True when reading has begun, so the button says "Resume" instead of "Start".
    var hasStartedReading: Bool {
        guard let next = nextChapter else { return false }
        return next.lastPageRead > 0 || chapters.contains { $0.read }
    }

    /// The next chapter only while something is unread; the continue button hides otherwise.
    var nextUnreadChapter: ChapterRecord? {
        chapters.contains { !$0.read } ? nextChapter : nil
    }

    /// The title's page on the source's website. `url` may be a path or already absolute.
    func webURL(baseUrl: String) -> String {
        if url.lowercased().hasPrefix("http://") || url.lowercased().hasPrefix("https://") { return url }
        return baseUrl + (url.hasPrefix("/") ? "" : "/") + url
    }
}

extension ChapterRecord {
    /// The chapter's page on the source's website. `url` may be a path or already absolute.
    func webURL(baseUrl: String) -> String {
        if url.lowercased().hasPrefix("http://") || url.lowercased().hasPrefix("https://") { return url }
        return baseUrl + (url.hasPrefix("/") ? "" : "/") + url
    }
}
