import SwiftUI

enum Route: Hashable {
    case source(String)
    case manga(MangaRef)
}

struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .source(let id): SourceBrowseView(sourceId: id)
        case .manga(let ref): MangaDetailView(ref: ref)
        }
    }
}
