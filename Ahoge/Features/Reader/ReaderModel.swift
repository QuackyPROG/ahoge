import Foundation

@MainActor
final class ReaderModel: ObservableObject {
    struct Section: Identifiable {
        let chapter: ChapterRecord
        let pages: [SourcePage]
        var id: String { chapter.url }
    }

    /// One scroll target: a page, or the card shown before the first chapter and after each one.
    struct Item: Identifiable {
        enum Kind {
            case page(SourcePage, index: Int, count: Int)
            /// Before `chapter`: the chapter that comes before it, if any.
            case start(previous: ChapterRecord?)
            /// After `chapter`: the chapter that comes next, if any.
            case end(next: ChapterRecord?)
        }

        let id: String
        let chapter: ChapterRecord
        let kind: Kind
    }

    let sourceId: String
    let manga: LibraryManga
    @Published private(set) var sections: [Section] = [] { didSet { items = Self.items(sections, model: self) } }
    @Published private(set) var items: [Item] = []
    @Published private(set) var error: Error?
    @Published private(set) var isLoadingNext = false
    @Published private(set) var currentChapter: ChapterRecord
    @Published private(set) var currentPage = 0
    /// The item at the top (webtoon) or on screen (paged). Bound to the scroll view.
    @Published var position: String?
    /// False while a chapter loads and the scroll view moves to its starting page.
    @Published private(set) var ready = false

    init(sourceId: String, manga: LibraryManga, start: ChapterRecord) {
        self.sourceId = sourceId
        self.manga = manga
        currentChapter = start
    }

    var currentSection: Section? { sections.first { $0.id == currentChapter.url } }

    static func pageID(_ chapterURL: String, _ index: Int) -> String { "\(chapterURL)#\(index)" }

    /// The next chapter to read: the closest newer one (lower sourceOrder).
    func chapter(after chapter: ChapterRecord) -> ChapterRecord? {
        manga.chapters.filter { $0.sourceOrder < chapter.sourceOrder }.max { $0.sourceOrder < $1.sourceOrder }
    }

    func chapter(before chapter: ChapterRecord) -> ChapterRecord? {
        manga.chapters.filter { $0.sourceOrder > chapter.sourceOrder }.min { $0.sourceOrder < $1.sourceOrder }
    }

    /// Shows only `chapter`, replacing what was loaded, at `page` (its saved page when nil).
    func open(_ chapter: ChapterRecord, page: Int? = nil, provider: PageProvider) async {
        ready = false
        error = nil
        sections = []
        position = nil
        currentChapter = chapter
        currentPage = 0
        do {
            let loaded = try await provider.pages(for: chapter)
            let pages = loaded.map(\.sourcePage)
            sections = [Section(chapter: chapter, pages: pages)]
            if case .local? = loaded.first { provider.downloads.readerOpened(chapter) }
            let start = page ?? (chapter.read ? 0 : chapter.lastPageRead)
            let index = min(max(start, 0), max(pages.count - 1, 0))
            currentPage = index
            // The scroll view only moves to an item it has laid out.
            try? await Task.sleep(nanoseconds: 60_000_000)
            position = Self.pageID(chapter.url, index)
            try? await Task.sleep(nanoseconds: 60_000_000)
        } catch {
            self.error = error
        }
        ready = true
    }

    /// Moves a new scroll view (after a reading mode change) to the item the old one showed.
    func reposition() async {
        guard ready, let target = position else { return }
        ready = false
        position = nil
        try? await Task.sleep(nanoseconds: 60_000_000)
        position = target
        try? await Task.sleep(nanoseconds: 60_000_000)
        ready = true
    }

    /// Scrolls to `page` of the current chapter.
    func jump(to page: Int) {
        guard let section = currentSection, section.pages.indices.contains(page) else { return }
        position = Self.pageID(section.id, page)
    }

    /// The item `offset` places from the current one, for tap zones and keys.
    func item(offset: Int) -> String? {
        guard let position, let index = items.firstIndex(where: { $0.id == position }) else { return nil }
        let target = index + offset
        return items.indices.contains(target) ? items[target].id : nil
    }

    /// Records progress for the item now on screen and loads what comes next.
    func positionChanged(repo: LibraryRepository, provider: PageProvider) {
        guard ready, let position, let index = items.firstIndex(where: { $0.id == position }) else { return }
        let item = items[index]
        switch item.kind {
        case .page(_, let page, let count):
            currentChapter = item.chapter
            currentPage = page
            let wasRead = item.chapter.read
            repo.saveProgress(item.chapter, page: page, pageCount: count)
            if !wasRead, item.chapter.read { provider.downloads.readerFinished(item.chapter) }
            for case .page(let next, _, _) in items.dropFirst(index + 1).prefix(5).map(\.kind) {
                Task { await ImageLoader.shared.prefetch(next.url, headers: next.headers) }
            }
            // Mihon starts on the next chapter a few pages before the end, so it is there when reached.
            if count - page <= 3 { loadNext(after: item.chapter, provider: provider) }
        case .end:
            if let count = sections.first(where: { $0.id == item.chapter.url })?.pages.count, count > 0 {
                let wasRead = item.chapter.read
                repo.saveProgress(item.chapter, page: count - 1, pageCount: count)
                if !wasRead, item.chapter.read { provider.downloads.readerFinished(item.chapter) }
            }
            loadNext(after: item.chapter, provider: provider)
        case .start:
            break
        }
    }

    func retryNext(provider: PageProvider) {
        guard let last = sections.last else { return }
        error = nil
        loadNext(after: last.chapter, provider: provider)
    }

    private func loadNext(after chapter: ChapterRecord, provider: PageProvider) {
        guard chapter.url == sections.last?.id, !isLoadingNext, error == nil, let next = self.chapter(after: chapter) else { return }
        isLoadingNext = true
        Task {
            defer { isLoadingNext = false }
            do {
                let pages = try await provider.pages(for: next).map(\.sourcePage)
                if !sections.contains(where: { $0.id == next.url }) {
                    sections.append(Section(chapter: next, pages: pages))
                }
                for page in pages.prefix(3) {
                    Task { await ImageLoader.shared.prefetch(page.url, headers: page.headers) }
                }
            } catch {
                self.error = error
            }
        }
    }

    private static func items(_ sections: [Section], model: ReaderModel) -> [Item] {
        guard let first = sections.first else { return [] }
        var items = [Item(id: "start\n" + first.id, chapter: first.chapter, kind: .start(previous: model.chapter(before: first.chapter)))]
        for section in sections {
            for (index, page) in section.pages.enumerated() {
                items.append(Item(id: pageID(section.id, index), chapter: section.chapter, kind: .page(page, index: index, count: section.pages.count)))
            }
            items.append(Item(id: "end\n" + section.id, chapter: section.chapter, kind: .end(next: model.chapter(after: section.chapter))))
        }
        return items
    }
}
