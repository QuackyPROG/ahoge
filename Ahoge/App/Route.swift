import SwiftUI

enum Route: Hashable {
    case source(String)
    /// A source's browse screen filtered to one genre (tapped on a manga page).
    case sourceGenre(String, genre: String)
    case manga(MangaRef)
}

struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .source(let id): SourceBrowseView(sourceId: id)
        case .sourceGenre(let id, let genre): SourceBrowseView(sourceId: id, genre: genre)
        case .manga(let ref): MangaDetailView(ref: ref)
        }
    }
}
