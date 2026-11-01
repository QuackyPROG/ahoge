import SwiftUI

@MainActor
final class SourceBrowseModel: ObservableObject {
    enum Feed: String, CaseIterable, Identifiable {
        case popular = "Popular"
        case latest = "Latest"
        case filtered = "Filter"
        var id: String { rawValue }
    }

    /// (feed, query, page, filters) -> page of results. Injected so the model is testable without JavaScript.
    typealias Fetch = (Feed, String, Int, FilterState) async throws -> MangaListPage

    let sourceId: String
    @Published private(set) var feed: Feed = .popular
    @Published var query = ""
    @Published private(set) var filters = FilterState.empty
    @Published private(set) var items: [MangaStub] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    private(set) var filtersLoaded = false
    private var page = 0
    private var hasNext = true
    private var generation = 0

    init(sourceId: String) {
        self.sourceId = sourceId
    }

    static func fetch(from manager: SourceManager, sourceId: String) -> Fetch {
        { feed, query, page, filters in
            let source = try await manager.source(sourceId)
            if !query.isEmpty || feed == .filtered { return try await source.search(query: query, page: page, filters: filters) }
            return feed == .latest ? try await source.latest(page: page) : try await source.popular(page: page)
        }
    }

    /// Loads the filter list once. A source whose filters fail to load browses without them.
    func loadFilters(_ load: () async throws -> [SourceFilter]) async {
        guard !filtersLoaded else { return }
        filtersLoaded = true
        filters = FilterState(filters: (try? await load()) ?? [])
    }

    /// Opens filtered to a genre when the source has a matching filter, else searches for it.
    func applyGenre(_ genre: String) {
        var state = filters
        if state.include(named: genre) {
            filters = state
            feed = .filtered
        } else {
            query = genre
        }
    }

    func select(_ feed: Feed, _ fetch: Fetch) async {
        self.feed = feed
        await reload(fetch)
    }

    func apply(_ filters: FilterState, _ fetch: Fetch) async {
        self.filters = filters
        feed = .filtered
        await reload(fetch)
    }

    func reload(_ fetch: Fetch) async {
        generation += 1
        items = []
        page = 0
        hasNext = true
        error = nil
        isLoading = false
        await loadMore(fetch)
    }

    func loadMore(_ fetch: Fetch) async {
        guard !isLoading, hasNext else { return }
        isLoading = true
        let current = generation
        let next = page + 1
        do {
            let result = try await fetch(feed, query.trimmingCharacters(in: .whitespaces), next, filters)
            guard current == generation else { return }
            let known = Set(items.map(\.url))
            items += result.manga.filter { !known.contains($0.url) }
            page = next
            hasNext = result.hasNextPage && !result.manga.isEmpty
        } catch {
            guard current == generation else { return }
            self.error = error
        }
        isLoading = false
    }

    /// A finished load returned nothing at all.
    var foundNothing: Bool { !hasNext && !isLoading && error == nil && items.isEmpty }

    func shouldLoadMore(after url: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.url == url }) else { return false }
        return index >= items.count - 6
    }
}

struct SourceBrowseView: View {
    @EnvironmentObject private var sources: SourceManager
    @StateObject private var model: SourceBrowseModel
    @State private var webTarget: WebTarget?
    @State private var editing: FilterState?
    private let genre: String?

    init(sourceId: String, genre: String? = nil) {
        self.genre = genre
        _model = StateObject(wrappedValue: SourceBrowseModel(sourceId: sourceId))
    }

    private var fetch: SourceBrowseModel.Fetch { SourceBrowseModel.fetch(from: sources, sourceId: model.sourceId) }

    var body: some View {
        let info = sources.installed(model.sourceId)
        ScrollView {
            chips
            if let error = model.error, model.items.isEmpty {
                ErrorStateView(error: error, retry: { Task { await model.reload(fetch) } }, openWeb: { webTarget = WebTarget(url: $0) })
            }
            if model.foundNothing {
                ContentUnavailableView("No results", systemImage: "magnifyingglass", description: Text(model.feed == .filtered ? "Try fewer filters." : "Try another search."))
                    .padding(.top, 40)
            }
            MangaGrid(
                items: model.items.map { MangaRef(sourceId: model.sourceId, url: $0.url, title: $0.title, cover: $0.cover) },
                onItemAppear: { ref in
                    if model.shouldLoadMore(after: ref.url) { Task { await model.loadMore(fetch) } }
                }
            )
            if model.isLoading { ProgressView().padding() }
        }
        .navigationTitle(genre ?? info?.name ?? "Source")
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always))
        .onSubmit(of: .search) { Task { await model.reload(fetch) } }
        .onChange(of: model.query) { old, query in
            if query.isEmpty, !old.isEmpty { Task { await model.reload(fetch) } }
        }
        .task {
            guard model.items.isEmpty else { return }
            await model.loadFilters { try await sources.source(model.sourceId).filters() }
            if let genre, model.query.isEmpty, model.feed != .filtered { model.applyGenre(genre) }
            await model.reload(fetch)
        }
        .refreshable { await model.reload(fetch) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let info {
                    Button { webTarget = WebTarget(url: info.baseUrl) } label: { Image(systemName: "globe") }
                        .accessibilityLabel("Open in web view")
                }
            }
        }
        .sheet(item: $webTarget) { WebViewSheet(target: $0) }
        .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            FilterSheet(
                state: Binding(get: { editing ?? model.filters }, set: { editing = $0 }),
                apply: { state in
                    editing = nil
                    Task { await model.apply(state, fetch) }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    /// Mihon-style feed chips. Filters stay in effect while searching.
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(.popular, title: "Popular", icon: "flame")
                chip(.latest, title: "Latest", icon: "clock")
                if !model.filters.isEmpty {
                    let count = model.filters.activeCount
                    Button { editing = model.filters } label: {
                        chipLabel(count > 0 ? "Filter · \(count)" : "Filter", icon: "line.3.horizontal.decrease", selected: model.feed == .filtered)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 4)
    }

    private func chip(_ feed: SourceBrowseModel.Feed, title: String, icon: String) -> some View {
        Button {
            guard model.feed != feed || !model.query.isEmpty else { return }
            model.query = ""
            Task { await model.select(feed, fetch) }
        } label: {
            chipLabel(title, icon: icon, selected: model.feed == feed && model.query.isEmpty)
        }
        .buttonStyle(.plain)
    }

    private func chipLabel(_ title: String, icon: String, selected: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: Capsule())
            .contentShape(Capsule())
    }
}
