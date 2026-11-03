import SwiftUI

enum AppTab: Hashable {
    case library, updates, history, browse, more
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
