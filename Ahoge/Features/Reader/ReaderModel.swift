import Foundation

@MainActor
final class ReaderModel: ObservableObject {
    struct Section: Identifiable {
        let chapter: ChapterRecord
        let pages: [SourcePage]
        var id: String { chapter.url }
    }

    /// How pages become scroll items, from the reader's settings.
    struct Layout: Equatable {
        /// Wide pages become two items, one per half.
        var splitWide = false
        /// Pages are paired into two-page spreads.
        var dualPage = false
        var rightToLeft = false
        /// Spreads start one page later (Mihon's "shift").
        var shiftSpreads = false
        /// Off: the card between two loaded chapters shows only when chapters are missing in between.
        var alwaysShowTransition = true
    }

    /// One page of a spread, in screen order.
    struct SpreadPage {
        let page: SourcePage
        let index: Int
    }

    /// One scroll target: a page (or half a page, or a spread), or the card shown before the first
    /// chapter and after each one.
    struct Item: Identifiable {
        enum Kind {
            /// The page, or the first page of a spread in reading order.
            case page(SourcePage, index: Int, count: Int)
            /// Before `chapter`: the chapter that comes before it, if any.
            case start(previous: ChapterRecord?)
            /// After `chapter`: the chapter that comes next, if any.
            case end(next: ChapterRecord?)
        }

        let id: String
        let chapter: ChapterRecord
        let kind: Kind
        /// Which half of a split wide page this item shows.
        var half: ImageTransform.Half? = nil
        /// Both pages of a two-page spread, left to right on screen; empty for a single page.
        var spread: [SpreadPage] = []
        /// The page ids this item shows, so a page can be found again after pages are re-paired.
        var pageIDs: [String] = []
    }

    let sourceId: String
    let manga: LibraryManga
    @Published private(set) var sections: [Section] = [] { didSet { rebuildItems() } }
    @Published private(set) var items: [Item] = []
    @Published private(set) var error: Error?
    @Published private(set) var isLoadingNext = false
    @Published private(set) var currentChapter: ChapterRecord
    @Published private(set) var currentPage = 0
    /// The item at the top (webtoon) or on screen (paged). Bound to the scroll view.
    @Published var position: String?
    /// False while a chapter loads and the scroll view moves to its starting page.
    @Published private(set) var ready = false
    var layout = Layout() { didSet { if layout != oldValue { rebuildItems() } } }
    /// Applied to prefetched pages (crop, colours), so they are ready when shown.
    var transform = ImageTransform.plain
    /// Set when the reader opens; the next and previous chapters skip their chapters.
    var excludedScanlators: Set<String> = [] { didSet { navigator = makeNavigator() } }
    private let rules: SkipRules
    private let display: ChapterDisplay
    private var navigator: ChapterNavigator!
    /// Sizes of pages decoded so far, by page id.
    private var pageSizes: [String: CGSize] = [:]

    init(sourceId: String, manga: LibraryManga, start: ChapterRecord, rules: SkipRules = .current(), display: ChapterDisplay? = nil) {
        self.sourceId = sourceId
        self.manga = manga
        self.rules = rules
        self.display = display ?? ChapterDisplay.load(for: manga.key)
        currentChapter = start
        navigator = makeNavigator()
    }

    private func makeNavigator() -> ChapterNavigator {
        ChapterNavigator(chapters: manga.chapters, display: display, excludedScanlators: excludedScanlators, rules: rules)
    }

    var currentSection: Section? { sections.first { $0.id == currentChapter.url } }

    static func pageID(_ chapterURL: String, _ index: Int) -> String { "\(chapterURL)#\(index)" }

    /// The next chapter to read, by the chapter list's order and the skip rules.
    func chapter(after chapter: ChapterRecord) -> ChapterRecord? { navigator.next(after: chapter) }

    func chapter(before chapter: ChapterRecord) -> ChapterRecord? { navigator.previous(before: chapter) }

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
            position = itemID(containing: Self.pageID(chapter.url, index))
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
        position = itemID(containing: Self.pageID(section.id, page))
    }

    /// The item `offset` places from the current one, for tap zones and keys.
    func item(offset: Int) -> String? {
        guard let position, let index = items.firstIndex(where: { $0.id == position }) else { return nil }
        let target = index + offset
        return items.indices.contains(target) ? items[target].id : nil
    }

    /// The item showing the page `pageID`: its own item, or the spread it is part of.
    func itemID(containing pageID: String) -> String? {
        items.first { $0.id == pageID || $0.pageIDs.contains(pageID) }?.id
    }

    /// A page's size became known (decoded on screen or prefetched). Only a page turning out wide
    /// changes the items, and only while wide pages split or spreads are paired.
    func learnSize(_ size: CGSize, of pageID: String) {
        let wasWide = pageSizes[pageID].map(PageGeometry.isWide) ?? false
        pageSizes[pageID] = size
        guard PageGeometry.isWide(size) != wasWide, layout.splitWide || layout.dualPage else { return }
        rebuildItems()
    }

    /// Records progress for the item now on screen and loads what comes next.
    func positionChanged(repo: LibraryRepository, provider: PageProvider) {
        guard ready, let position, let index = items.firstIndex(where: { $0.id == position }) else { return }
        let item = items[index]
        switch item.kind {
        case .page(_, let first, let count):
            // A spread counts as read up to its later page.
            let page = item.spread.map(\.index).max() ?? first
            currentChapter = item.chapter
            currentPage = page
            let wasRead = item.chapter.read
            repo.saveProgress(item.chapter, page: page, pageCount: count)
            if !wasRead, item.chapter.read { provider.downloads.readerFinished(item.chapter) }
            // "Preload only on Wi-Fi": on cellular, only the next page.
            let ahead = Pref.readerPreloadOnlyOnWiFi.value() && provider.downloads.isOnExpensiveNetwork ? 1 : 5
            for next in items.dropFirst(index + 1).prefix(ahead) {
                for (page, id) in Self.pages(of: next) { prefetch(page, id: id) }
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


    // MARK: Reading time

    /// When the clock started and which chapter it counts for, nil while paused. Time is credited to
    /// the chapter the clock started on, so a chapter change flushes it first.
    private var clockSince: Date?
    private var clockChapter: ChapterRecord?
    /// A reader left open (screen kept on) must not count for hours.
    private static let longestStretch: TimeInterval = 30 * 60

    func startClock(now: Date = Date()) {
        guard ready, error == nil, clockSince == nil else { return }
        clockSince = now
        clockChapter = currentChapter
    }

    /// Saves the whole seconds read since the clock started (to history, unless incognito) and pauses it.
    func stopClock(repo: LibraryRepository, now: Date = Date()) {
        guard let since = clockSince, let chapter = clockChapter else { return }
        clockSince = nil
        clockChapter = nil
        let seconds = min(now.timeIntervalSince(since), Self.longestStretch)
        if seconds >= 1 { repo.addReadingTime(Int(seconds), to: chapter) }
    }

    /// The reader moved to another chapter: credit the old one and start counting the new one.
    func restartClock(repo: LibraryRepository, now: Date = Date()) {
        stopClock(repo: repo, now: now)
        startClock(now: now)
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
                let ahead = Pref.readerPreloadOnlyOnWiFi.value() && provider.downloads.isOnExpensiveNetwork ? 1 : 3
                for (index, page) in pages.prefix(ahead).enumerated() {
                    prefetch(page, id: Self.pageID(next.url, index))
                }
            } catch {
                self.error = error
            }
        }
    }

    /// Loads a page below the one on screen and notes its size; the transformed copy follows.
    private func prefetch(_ page: SourcePage, id: String) {
        let transform = transform
        Task { [weak self] in
            guard let image = try? await ImageLoader.shared.image(page.url, headers: page.headers, priority: .utility) else { return }
            self?.learnSize(image.size, of: id)
            if !transform.isIdentity { await ImageLoader.shared.prefetch(page.url, headers: page.headers, transform: transform) }
        }
    }

    /// The pages an item shows, with their page ids.
    private static func pages(of item: Item) -> [(SourcePage, String)] {
        guard case .page(let page, let index, _) = item.kind else { return [] }
        if item.spread.isEmpty { return [(page, pageID(item.chapter.url, index))] }
        return item.spread.map { ($0.page, pageID(item.chapter.url, $0.index)) }
    }

    private func rebuildItems() {
        items = buildItems()
        // A page that joined or left a spread (or a half that is whole again) now has another item: follow it.
        if let position, !items.contains(where: { $0.id == position }) {
            let page = position.replacingOccurrences(of: Self.secondHalfSuffix, with: "")
            if let owner = itemID(containing: page) { self.position = owner }
        }
    }

    private static let secondHalfSuffix = "\nsecond"

    private func buildItems() -> [Item] {
        guard let first = sections.first else { return [] }
        var items = [Item(id: "start\n" + first.id, chapter: first.chapter, kind: .start(previous: chapter(before: first.chapter)))]
        for (number, section) in sections.enumerated() {
            items += pageItems(section)
            let next = chapter(after: section.chapter)
            let endID = "end\n" + section.id
            let isLast = number == sections.count - 1
            // Kept while on screen, so the scroll view never loses the item it shows.
            if layout.alwaysShowTransition || isLast || position == endID || Self.hasGap(from: section.chapter, to: next) {
                items.append(Item(id: endID, chapter: section.chapter, kind: .end(next: next)))
            }
        }
        return items
    }

    /// Chapters are missing between `chapter` and `next` (Mihon shows the card for these).
    private static func hasGap(from chapter: ChapterRecord, to next: ChapterRecord?) -> Bool {
        guard let next, chapter.number >= 0, next.number >= 0 else { return false }
        return abs(next.number.rounded(.down) - chapter.number.rounded(.down)) > 1
    }

    private func pageItems(_ section: Section) -> [Item] {
        let count = section.pages.count
        let ids = (0..<count).map { Self.pageID(section.id, $0) }
        func single(_ index: Int, half: ImageTransform.Half? = nil) -> Item {
            Item(
                id: half == .second ? ids[index] + Self.secondHalfSuffix : ids[index],
                chapter: section.chapter,
                kind: .page(section.pages[index], index: index, count: count),
                half: half,
                pageIDs: half == .second ? [] : [ids[index]]
            )
        }
        if layout.dualPage {
            var sizes: [Int: CGSize] = [:]
            for (index, id) in ids.enumerated() { sizes[index] = pageSizes[id] }
            return PagePairing.pairs(pages: count, sizes: sizes, rtl: layout.rightToLeft, firstAlone: layout.shiftSpreads).map { group -> Item in
                guard group.count > 1 else { return single(group[0]) }
                let first = group.min() ?? group[0]
                return Item(
                    id: ids[first],
                    chapter: section.chapter,
                    kind: .page(section.pages[first], index: first, count: count),
                    spread: group.map { SpreadPage(page: section.pages[$0], index: $0) },
                    pageIDs: group.map { ids[$0] }
                )
            }
        }
        var items: [Item] = []
        for index in 0..<count {
            if layout.splitWide, let size = pageSizes[ids[index]], PageGeometry.isWide(size) {
                items.append(single(index, half: .first))
                items.append(single(index, half: .second))
            } else {
                items.append(single(index))
            }
        }
        return items
    }
}
