import SwiftUI

@MainActor
final class SourceBrowseModel: ObservableObject {
    enum Feed: String, CaseIterable, Identifiable {
        case popular = "Popular"
        case latest = "Latest"
        var id: String { rawValue }
    }

    /// (feed, query, page) -> page of results. Injected so the model is testable without JavaScript.
    typealias Fetch = (Feed, String, Int) async throws -> MangaListPage

    let sourceId: String
    @Published var feed: Feed = .popular
    @Published var query = ""
    @Published private(set) var items: [MangaStub] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    private var page = 0
    private var hasNext = true
    private var generation = 0

    init(sourceId: String) {
        self.sourceId = sourceId
    }

    static func fetch(from manager: SourceManager, sourceId: String) -> Fetch {
        { feed, query, page in
            let source = try await manager.source(sourceId)
            if !query.isEmpty { return try await source.search(query: query, page: page) }
            return feed == .latest ? try await source.latest(page: page) : try await source.popular(page: page)
        }
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
            let result = try await fetch(feed, query.trimmingCharacters(in: .whitespaces), next)
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

    func shouldLoadMore(after url: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.url == url }) else { return false }
        return index >= items.count - 6
    }
}

struct SourceBrowseView: View {
    @EnvironmentObject private var sources: SourceManager
    @StateObject private var model: SourceBrowseModel
    @State private var webTarget: WebTarget?

    init(sourceId: String) {
        _model = StateObject(wrappedValue: SourceBrowseModel(sourceId: sourceId))
    }

    private var fetch: SourceBrowseModel.Fetch { SourceBrowseModel.fetch(from: sources, sourceId: model.sourceId) }

    var body: some View {
        let info = sources.installed(model.sourceId)
        ScrollView {
            Picker("Feed", selection: $model.feed) {
                ForEach(SourceBrowseModel.Feed.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .disabled(!model.query.isEmpty)

            if let error = model.error, model.items.isEmpty {
                ErrorStateView(error: error, retry: { Task { await model.reload(fetch) } }, openWeb: { webTarget = WebTarget(url: $0) })
            }
            MangaGrid(
                items: model.items.map { MangaRef(sourceId: model.sourceId, url: $0.url, title: $0.title, cover: $0.cover) },
                onItemAppear: { ref in
                    if model.shouldLoadMore(after: ref.url) { Task { await model.loadMore(fetch) } }
                }
            )
            if model.isLoading { ProgressView().padding() }
        }
        .navigationTitle(info?.name ?? "Source")
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always))
        .onSubmit(of: .search) { Task { await model.reload(fetch) } }
        .onChange(of: model.query) { _, query in
            if query.isEmpty { Task { await model.reload(fetch) } }
        }
        .onChange(of: model.feed) { _, _ in Task { await model.reload(fetch) } }
        .task { if model.items.isEmpty { await model.reload(fetch) } }
        .refreshable { await model.reload(fetch) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let info {
                    Button { webTarget = WebTarget(url: info.baseUrl) } label: { Image(systemName: "globe") }
                }
            }
        }
        .sheet(item: $webTarget) { WebViewSheet(target: $0) }
    }
}
