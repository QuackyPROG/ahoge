import SwiftUI

enum AppTab: Hashable, CaseIterable {
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

/// Asks the interface to go somewhere from outside a view: a notification tap, and later deep links.
/// RootView follows `tab`; the Library tab consumes `pendingRoute` and pushes it.
@MainActor
final class AppNavigator: ObservableObject {
    /// A singleton because system callbacks (notification taps) have no view to reach it from.
    static let shared = AppNavigator()

    @Published var tab: AppTab = .library
    @Published var pendingRoute: Route?
    /// A repository link waiting for the person to confirm adding it.
    @Published var pendingRepo: URL?
    /// Each tab's navigation stack, so any view can push onto the visible tab.
    @Published var paths: [AppTab: [Route]] = [:]

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

    /// Shows `route` on top of the Library tab.
    func open(_ route: Route) {
        tab = .library
        pendingRoute = route
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
