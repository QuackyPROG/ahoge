import Foundation

/// Hooks that apply `DownloadRules`: called by the repository, the reader and library updates.
extension DownloadManager {
    private var rules: DownloadRules.Settings { DownloadRules.Settings.current(defaults) }

    /// "Remove after marked as read".
    func chaptersMarkedRead(_ chapters: [ChapterRecord]) {
        let targets = DownloadRules.chaptersToDelete(markedRead: chapters.filter { isDownloaded($0.key) }, prefs: rules)
        delete(targets)
    }

    /// The reader opened `chapter`: download ahead when its pages were on disk.
    func readerOpened(_ chapter: ChapterRecord) {
        guard let manga = chapter.manga else { return }
        let done = Set(manga.chapters.map(\.key).filter { isDownloaded($0) })
        enqueue(DownloadRules.chaptersToDownloadAhead(current: chapter, in: manga.chapters, inLibrary: manga.inLibrary, downloaded: done, prefs: rules))
    }

    /// The reader finished `chapter`: notes what "Remove after reading" picks, deleted on close.
    func readerFinished(_ chapter: ChapterRecord) {
        guard let manga = chapter.manga else { return }
        let targets = DownloadRules.chaptersToDelete(after: chapter, in: manga.chapters, prefs: rules).filter { isDownloaded($0.key) }
        pendingDeletes.append(contentsOf: targets.filter { target in !pendingDeletes.contains { $0.key == target.key } })
    }

    func readerClosed() {
        let targets = pendingDeletes
        pendingDeletes = []
        delete(targets)
    }

    /// A library update found `new` chapters of `manga` (which had chapters before).
    func chaptersFound(_ new: [ChapterRecord], in manga: LibraryManga) {
        let ids = repo.categoryIds(of: manga)
        let categories = repo.categories.filter { ids.contains($0.id) }
        enqueue(DownloadRules.chaptersToAutoDownload(new: new, manga: manga, categories: categories, prefs: rules))
    }
}
