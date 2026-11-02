import SwiftUI

struct MangaGrid: View {
    let items: [MangaRef]
    var badge: (MangaRef) -> String? = { _ in nil }
    var onItemAppear: (MangaRef) -> Void = { _ in }
    @EnvironmentObject private var sources: SourceManager

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12, alignment: .top)], spacing: 12) {
            ForEach(items, id: \.self) { ref in
                NavigationLink(value: Route.manga(ref)) {
                    MangaCard(title: ref.title, cover: ref.cover, headers: referer(ref), badge: badge(ref))
                }
                .buttonStyle(PressableCardStyle())
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contextMenu { LibraryToggleButton(ref: ref) }
                .onAppear { onItemAppear(ref) }
            }
        }
        .padding(.horizontal)
    }

    private func referer(_ ref: MangaRef) -> [String: String] {
        sources.installed(ref.sourceId).map { ["Referer": $0.baseUrl + "/"] } ?? [:]
    }
}
