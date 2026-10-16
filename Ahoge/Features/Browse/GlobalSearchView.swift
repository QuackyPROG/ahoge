import SwiftUI

struct GlobalSearchView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var submitted = ""
    @State private var searchGeneration = SearchGeneration()
    @State private var task: Task<Void, Never>?
    @State private var retryTasks: [String: Task<Void, Never>] = [:]
    @State private var groupRunning = false
    @State private var results: [String: [Manga]] = [:]
    @State private var errors: [String: String] = [:]
    @State private var loading: Set<String> = []
    @State private var searchedSources: [Source] = []
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                NavigationLink("Source filters") { SourcesFilterView() }
                if submitted.isEmpty {
                    ContentUnavailableView("Search all sources", systemImage: "magnifyingglass", description: Text("Submit a title to search enabled sources. Results appear as each source responds."))
                } else {
                    ForEach(searchedSources) { source in
                        VStack(alignment: .leading, spacing: 12) {
                            NavigationLink(source.name) { SourceView(source: source) }.font(.headline)
                            if loading.contains(source.id) { ProgressView("Searching") }
                            if let error = errors[source.id] {
                                Label(error, systemImage: "exclamationmark.triangle").font(.footnote)
                                Button("Retry this source") { retry(source) }.disabled(groupRunning || retryTasks.count >= 4 || loading.contains(source.id))
                            }
                            if results[source.id]?.isEmpty == true && !loading.contains(source.id) { Text("No results").foregroundStyle(.secondary) }
                            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 112))]) {
                                ForEach(results[source.id] ?? []) { manga in
                                    NavigationLink { MangaDetailView(manga: manga) } label: {
                                        AhogeMangaGridCard(manga: manga, hideSensitiveCover: model.state.securityPreferences.hideSensitiveCovers,
                                            allowsAdultContent: source.allowsAdultContent, badgeText: model.isInLibrary(manga) ? "Library" : nil)
                                    }.buttonStyle(.plain).contextMenu {
                                        Button(model.isInLibrary(manga) ? "Remove from Library" : "Add to Library") { model.toggleLibrary(manga) }
                                            .disabled(model.state.securityPreferences.lockLibraryEdits)
                                    }
                                }
                            }
                        }
                    }
                    if searchedSources.isEmpty { ContentUnavailableView("No enabled sources", systemImage: "globe", description: Text("Enable sources or import local files in Browse.")) }
                }
            }.padding()
        }
        .navigationTitle("Global Search")
        .searchable(text: $query, prompt: "Search title")
        .onSubmit(of: .search) { search() }
        .onChange(of: query) { _, _ in cancel() }
        .onChange(of: model.state.sourceEnabledOverrides) { _, _ in cancel() }
        .onChange(of: model.state.packageInstallations) { _, _ in cancel() }
        .onChange(of: model.sources) { _, _ in cancel() }
        .onChange(of: model.state.browsePreferences) { _, _ in cancel() }
        .onDisappear { cancel() }
    }

    private func cancel() { searchGeneration.invalidate(); task?.cancel(); task = nil; retryTasks.values.forEach { $0.cancel() }; retryTasks = [:]; loading = []; groupRunning = false }

    private func search() {
        cancel()
        submitted = query.trimmingCharacters(in: .whitespacesAndNewlines)
        results = [:]; errors = [:]
        guard !submitted.isEmpty else { return }
        searchedSources = model.visibleSources.filter { model.sourceIsEnabled($0) }
        loading = Set(searchedSources.map(\.id))
        let token = searchGeneration.token, text = submitted, sources = searchedSources
        groupRunning = true
        task = Task { @MainActor in
            defer { if searchGeneration.accepts(token) { groupRunning = false; task = nil } }
            await withTaskGroup(of: (String, [Manga]?, String?).self) { group in
                var iterator = sources.makeIterator()
                func add(_ source: Source) {
                    group.addTask { @MainActor in
                        do { return (source.id, try await model.searchSource(source, query: text), nil) }
                        catch { return (source.id, nil, error.localizedDescription) }
                    }
                }
                for _ in 0..<4 { if let source = iterator.next() { add(source) } }
                for await (id, items, error) in group {
                    guard !Task.isCancelled, searchGeneration.accepts(token) else { group.cancelAll(); return }
                    loading.remove(id)
                    if let items { results[id] = unique(items) }
                    if let error { errors[id] = error }
                    if let source = iterator.next() { add(source) }
                }
            }
        }
    }

    private func retry(_ source: Source) {
        guard !groupRunning, retryTasks.count < 4, !loading.contains(source.id) else { return }
        let token = searchGeneration.token, text = submitted
        loading.insert(source.id); errors[source.id] = nil
        retryTasks[source.id] = Task { @MainActor in
            defer { if searchGeneration.accepts(token) { retryTasks[source.id] = nil } }
            do {
                let items = try await model.searchSource(source, query: text)
                guard !Task.isCancelled, searchGeneration.accepts(token) else { return }
                results[source.id] = unique(items)
            } catch {
                guard !Task.isCancelled, searchGeneration.accepts(token) else { return }
                errors[source.id] = error.localizedDescription
            }
            loading.remove(source.id)
        }
    }

    private func unique(_ items: [Manga]) -> [Manga] { var ids = Set<String>(); return items.filter { ids.insert($0.id).inserted } }
}
