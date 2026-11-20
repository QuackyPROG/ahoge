import SwiftUI

enum AppTab: String, Hashable, CaseIterable, Codable {
    case library, updates, history, browse, more

    var title: String {
        switch self {
        case .library: "Library"
        case .updates: "Updates"
        case .history: "History"
        case .browse: "Browse"
        case .more: "More"
        }
    }

    var symbol: String {
        switch self {
        case .library: "books.vertical"
        case .updates: "bell"
        case .history: "clock.arrow.circlepath"
        case .browse: "safari"
        case .more: "ellipsis.circle"
        }
    }
}

struct OpenReader: Identifiable {
    let sourceId: String
    let manga: LibraryManga
    let chapter: ChapterRecord
    /// The page to open at; nil is the chapter's saved page.
    var page: Int? = nil
    var id: String { chapter.key }
}

/// Where the app was, saved on every change and reopened on a cold launch. Incognito keeps only `tab`.
struct NavigationSnapshot: Codable {
    var tab: AppTab
    /// The top-most manga page of `tab`.
    var manga: MangaRef?
    var readerManga: String?
    var readerChapter: String?
    var readerPage: Int?
}
/// Asks the interface to go somewhere from outside a view: a notification tap, and later deep links.
/// RootView follows `tab`; each tab's stack follows its path.
@MainActor
final class AppNavigator: ObservableObject {
    /// A singleton because system callbacks (notification taps) have no view to reach it from.
    static let shared = AppNavigator()

    @Published var tab: AppTab = .library { didSet { save() } }
    /// Changes when every tab-screen sheet and cover should close (`dismissOnRoute`).
    @Published private(set) var dismissRequest = 0
    /// A repository link waiting for the person to confirm adding it.
    @Published var pendingRepo: URL?
    /// Each tab's navigation stack, so any view can push onto the visible tab.
    @Published var paths: [AppTab: [Route]] = [:] { didSet { save() } }

    func path(for tab: AppTab) -> [Route] { paths[tab] ?? [] }

    /// For a tab root's `NavigationStack(path:)`.
    func binding(for tab: AppTab) -> Binding<[Route]> {
        Binding(get: { self.path(for: tab) }, set: { self.paths[tab] = $0 })
    }

    /// Shows `route` on top of the selected tab.
    func push(_ route: Route) {
        paths[tab, default: []].append(route)
    }

    /// After migrating `old` to `new` on the selected tab: Back never returns to a search for the old entry.
    func finishMigration(from old: MangaRef, to new: MangaRef) {
        paths[tab] = .finishingMigration(path(for: tab), from: old, to: new)
    }

    /// The chapter open in the reader, presented by RootView. Holds the manga strongly: `ChapterRecord.manga` is weak.
    @Published var reader: OpenReader? {
        didSet {
            readerChapter = reader?.chapter
            readerPage = reader?.page
            save()
        }
    }
    /// Where the reader is now; it moves on from the chapter it opened.
    private var readerChapter: ChapterRecord?
    private var readerPage: Int?
    /// Set by `restore`; nothing is saved before it.
    private var defaults: UserDefaults?
    private var repo: LibraryRepository?

    func read(_ chapter: ChapterRecord, in manga: LibraryManga) {
        reader = OpenReader(sourceId: manga.sourceId, manga: manga, chapter: chapter)
    }

    func closeReader() { reader = nil }

    /// The reader shows `page` of `chapter`.
    func readerMoved(to chapter: ChapterRecord, page: Int) {
        readerChapter = chapter
        readerPage = page
        save()
    }

    /// Cold launch: reopens the saved tab, its top manga page and the reader, skipping titles and chapters
    /// that are gone, then saves every change to `defaults`.
    func restore(from defaults: UserDefaults = .standard, repo: LibraryRepository) {
        self.repo = repo
        if let data = Pref.navigationSnapshot.value(in: defaults), let saved = try? JSONDecoder().decode(NavigationSnapshot.self, from: data) {
            tab = saved.tab
            if let ref = saved.manga, repo.manga(sourceId: ref.sourceId, url: ref.url) != nil {
                paths[saved.tab] = [.manga(ref)]
            }
            if let key = saved.readerManga, let manga = repo.manga(key: key),
               let chapter = manga.chapters.first(where: { $0.key == saved.readerChapter }) {
                reader = OpenReader(sourceId: manga.sourceId, manga: manga, chapter: chapter, page: saved.readerPage)
            }
        }
        self.defaults = defaults
        save()
    }

    /// Writes the snapshot; while incognito applies to the open title, only the tab.
    private func save() {
        guard let defaults else { return }
        var ref: MangaRef?
        for case .manga(let found) in path(for: tab) { ref = found }
        let titleSources = [ref?.sourceId, reader?.sourceId].compactMap { $0 }
        var snapshot = NavigationSnapshot(tab: tab)
        if !titleSources.contains(where: { repo?.isIncognito(sourceId: $0) == true }) {
            snapshot.manga = ref
            if let reader {
                snapshot.readerManga = reader.manga.key
                snapshot.readerChapter = readerChapter?.key
                snapshot.readerPage = readerPage
            }
        }
        if let data = try? JSONEncoder().encode(snapshot) { Pref.navigationSnapshot.set(data, in: defaults) }
    }

    /// Selects `tab`, closing the reader and every sheet first so nothing covers it.
    func show(_ tab: AppTab) {
        closeReader()
        dismissRequest += 1
        self.tab = tab
    }

    /// Shows `route` on top of the Library tab, closing the reader and every sheet first so nothing covers it.
    func open(_ route: Route) {
        show(.library)
        paths[.library, default: []].append(route)
    }

    /// Follows a link opened from outside: `ahoge://` or a source's web address. Returns whether it meant anything.
    @discardableResult
    func open(_ url: URL, sources: [InstalledSource]) -> Bool {
        guard let link = DeepLinkResolver.resolve(url, sources: sources) else { return false }
        open(link)
        return true
    }

    func open(_ link: DeepLink) {
        switch link {
        case .manga(let sourceId, let path): open(.manga(MangaRef(sourceId: sourceId, url: path, title: "", cover: "")))
        case .search(let query): open(.globalSearch(query))
        case .addRepo(let url): pendingRepo = url
        }
    }
}

extension [Route] {
    /// Mihon's rule: the new entry's page replaces the old page and its migrate search. Started from
    /// More > Migrate, the migrate search and everything above it close, back to the titles list.
    static func finishingMigration(_ path: [Route], from old: MangaRef, to new: MangaRef) -> [Route] {
        // By source and url: a page opened from a link has no title or cover yet.
        func isOld(_ ref: MangaRef) -> Bool { ref.sourceId == old.sourceId && ref.url == old.url }
        guard let index = path.lastIndex(where: {
            guard case .migrate(let ref) = $0 else { return false }
            return isOld(ref)
        }) else { return path }
        if index > 0, case .manga(let ref) = path[index - 1], isOld(ref) {
            return Array(path[..<(index - 1)]) + [.manga(new)]
        }
        return Array(path[..<index])
    }
}
extension View {
    /// Clears a screen's sheets and covers when a notification tap or deep link opens a route over everything.
    func dismissOnRoute(_ clear: @escaping () -> Void) -> some View {
        modifier(DismissOnRoute(clear: clear))
    }
}

private struct DismissOnRoute: ViewModifier {
    @EnvironmentObject private var navigator: AppNavigator
    let clear: () -> Void
    func body(content: Content) -> some View {
        content.onChange(of: navigator.dismissRequest) { clear() }
    }
}
