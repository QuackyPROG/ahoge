import SwiftUI

enum Route: Hashable {
    case source(String)
    /// A source's browse screen filtered to one genre (tapped on a manga page).
    case sourceGenre(String, genre: String)
    /// A source's browse screen with a search already typed (tapped on an author).
    case sourceSearch(String, query: String)
    case manga(MangaRef)
    /// Search every source for a query. Phase 6 builds the screen; until `GlobalSearchAvailable.isOn`, nothing links here.
    case globalSearch(String)
}

/// Switched on by the task that adds global search, so the Library's "Search globally" row stays hidden until then.
enum GlobalSearchAvailable {
    static let isOn = false
}

struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .source(let id): SourceBrowseView(sourceId: id)
        case .sourceGenre(let id, let genre): SourceBrowseView(sourceId: id, genre: genre)
        case .sourceSearch(let id, let query): SourceBrowseView(sourceId: id, query: query)
        case .manga(let ref): MangaDetailView(ref: ref)
        // Replaced by the global search screen in Phase 6; unreachable while `GlobalSearchAvailable.isOn` is false.
        case .globalSearch: EmptyView()
        }
    }
}
