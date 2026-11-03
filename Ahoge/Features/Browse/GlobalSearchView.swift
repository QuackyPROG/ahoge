import SwiftUI

/// Searches every visible source at once: one row of results per source (Mihon's global search).
struct GlobalSearchView: View {
    let query: String
    @EnvironmentObject private var sources: SourceManager

    var body: some View {
        GlobalSearchScreen(initialQuery: query, makeSearch: GlobalSearch(searcher: GlobalSearch.searcher(from: sources)))
    }
}

private struct GlobalSearchScreen: View {
    @EnvironmentObject private var store: ExtensionStore
    @EnvironmentObject private var repo: LibraryRepository
    @StateObject private var search: GlobalSearch
    @State private var query: String
    @State private var searched = ""
    @AppStorage(Pref.globalSearchPinnedOnly.name) private var pinnedOnly = false
    @State private var onlyWithResults = false
    @Environment(\.palette) private var palette

    init(initialQuery: String, makeSearch: @autoclosure @escaping () -> GlobalSearch) {
        _query = State(initialValue: initialQuery)
        _search = StateObject(wrappedValue: makeSearch())
    }

    var body: some View {
        let shown = onlyWithResults ? search.results.filter(\.hasResults) : search.results
        ScrollView {
            chips
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(shown) { result in
                    section(result)
                }
            }
            .padding(.vertical, 8)
            if !searched.isEmpty, search.results.isEmpty {
                ContentUnavailableView("No sources to search", systemImage: "puzzlepiece.extension", description: Text(pinnedOnly ? "Pin a source or turn off Pinned only." : "Install or enable sources in Browse."))
                    .padding(.top, 40)
            }
        }
        .navigationTitle("Global search")
        .navigationBarTitleDisplayMode(.inline)
        .themedScreen()
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search all sources")
        .onSubmit(of: .search) { start() }
        .onChange(of: pinnedOnly) { start() }
        .task { if searched.isEmpty { start() } }
        .onDisappear { search.cancel() }
    }

    private func start() {
        searched = query
        let eligible = GlobalSearch.eligible(
            store.installed,
            visibility: .current(),
            pinned: Pref.pinnedSources.value(),
            pinnedOnly: pinnedOnly
        )
        search.run(query, sources: eligible)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Pinned only", icon: "pin", on: $pinnedOnly)
                chip("Has results", icon: "checkmark.circle", on: $onlyWithResults)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 4)
    }

    private func chip(_ title: String, icon: String, on: Binding<Bool>) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(on.wrappedValue ? palette.onPrimary.color : Color.primary)
                .background(on.wrappedValue ? AnyShapeStyle(palette.primary.color) : AnyShapeStyle(.quaternary), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on.wrappedValue ? .isSelected : [])
    }

    @ViewBuilder
    private func section(_ result: GlobalSearch.SourceResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // The header opens the source with the same search, for more than the first page.
            NavigationLink(value: Route.sourceSearch(result.source.id, query: searched)) {
                HStack(spacing: 10) {
                    RemoteImage(url: result.source.iconURL ?? "")
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(result.source.name).font(.headline)
                        Text(result.source.lang.uppercased()).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.forward").foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            switch result.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 60)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal)
            case .done(let manga) where manga.isEmpty:
                Text("No results").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            case .done(let manga):
                carousel(manga, source: result.source)
            }
        }
    }

    private func carousel(_ manga: [MangaStub], source: InstalledSource) -> some View {
        let headers = ["Referer": source.baseUrl + "/"]
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 10) {
                ForEach(manga, id: \.url) { stub in
                    let ref = MangaRef(sourceId: source.id, url: stub.url, title: stub.title, cover: stub.cover)
                    NavigationLink(value: Route.manga(ref)) {
                        MangaCard(title: stub.title, cover: stub.cover, headers: headers, inLibrary: inLibrary(ref))
                            .frame(width: 110)
                    }
                    .buttonStyle(PressableCardStyle())
                }
            }
            .padding(.horizontal)
        }
    }

    private func inLibrary(_ ref: MangaRef) -> Bool {
        repo.manga(sourceId: ref.sourceId, url: ref.url)?.inLibrary == true
    }
}
