import SwiftUI

struct MangaGrid: View {
    let items: [MangaRef]
    var badge: (MangaRef) -> String? = { _ in nil }
    var onItemAppear: (MangaRef) -> Void = { _ in }
    /// Browse results already saved to the library, to fade.
    var isInLibrary: (MangaRef) -> Bool = { _ in false }
    /// In the Library: opens the title's next unread chapter. Nil (or false from `canContinue`) shows no play button.
    var onContinue: ((MangaRef) -> Void)? = nil
    var canContinue: (MangaRef) -> Bool = { _ in false }
    /// When set, taps toggle selection (by manga key) instead of opening the manga.
    var selection: Binding<Set<String>>? = nil
    /// In the Library: starts selection from a long-press, and offers "Edit categories".
    var librarySelect: ((MangaRef) -> Void)? = nil
    @EnvironmentObject private var sources: SourceManager
    @Environment(\.palette) private var palette
    @State private var choosingCategories: LibraryManga?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12, alignment: .top)], spacing: 12) {
            ForEach(items, id: \.self) { ref in
                cell(ref).onAppear { onItemAppear(ref) }
            }
        }
        .padding(.horizontal)
        .sheet(item: $choosingCategories) { SetCategoriesSheet(manga: [$0]) }
    }

    @ViewBuilder
    private func cell(_ ref: MangaRef) -> some View {
        let card = MangaCard(title: ref.title, cover: ref.cover, headers: referer(ref), badge: badge(ref), inLibrary: isInLibrary(ref))
        if let selection {
            let key = LibraryManga.makeKey(sourceId: ref.sourceId, url: ref.url)
            let selected = selection.wrappedValue.contains(key)
            Button {
                if selected { selection.wrappedValue.remove(key) } else { selection.wrappedValue.insert(key) }
            } label: {
                card
                    .overlay {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.primary.color.opacity(selected ? 0.25 : 0))
                            RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.primary.color, lineWidth: selected ? 3 : 0)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(selected ? palette.onPrimary.color : Color.white, selected ? palette.primary.color : Color.black.opacity(0.35))
                            .padding(6)
                            .accessibilityHidden(true)
                    }
            }
            .buttonStyle(PressableCardStyle())
            .sensoryFeedback(.selection, trigger: selected)
            .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            NavigationLink(value: Route.manga(ref)) { card }
                .buttonStyle(PressableCardStyle())
                .overlay(alignment: .bottomTrailing) {
                    if let onContinue, canContinue(ref) {
                        Button { onContinue(ref) } label: {
                            Image(systemName: "play.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(palette.onPrimary.color)
                                .frame(width: 30, height: 30)
                                .background(palette.primary.color, in: Circle())
                                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                                .padding(6)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Continue reading \(ref.title)")
                    }
                }
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contextMenu {
                    LibraryCardMenu(ref: ref, librarySelect: librarySelect) { target in
                        Task { @MainActor in choosingCategories = target }
                    }
                }
        }
    }

    private func referer(_ ref: MangaRef) -> [String: String] {
        sources.installed(ref.sourceId).map { ["Referer": $0.baseUrl + "/"] } ?? [:]
    }
}

/// Context-menu contents; holds the repo so the grid itself does not re-render on every repo change.
private struct LibraryCardMenu: View {
    let ref: MangaRef
    let librarySelect: ((MangaRef) -> Void)?
    let choose: (LibraryManga?) -> Void
    @EnvironmentObject private var repo: LibraryRepository

    var body: some View {
        if let librarySelect {
            Button("Select", systemImage: "checkmark.circle") { librarySelect(ref) }
            Button("Edit categories", systemImage: "folder") {
                choose(repo.manga(sourceId: ref.sourceId, url: ref.url))
            }
        }
        LibraryToggleButton(ref: ref) { added in choose(added) }
    }
}
