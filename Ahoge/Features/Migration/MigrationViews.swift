import SwiftUI

struct MigrationSourcesView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        List {
            Text("Choose the original library source. Downloaded files stay with the original edition.").foregroundStyle(.secondary)
            ForEach(model.sources.filter { source in model.state.library.contains { entry in model.allMangaByID()[entry.mangaID]?.sourceID == source.id } }) { source in
                NavigationLink { MigrationSearchView(source: source) } label: { SourceRow(source: source) }
            }
            if model.state.library.isEmpty { ContentUnavailableView("No library titles", systemImage: "books.vertical") }
        }.navigationTitle("Migration")
    }
}

struct MigrationSearchView: View {
    @EnvironmentObject private var model: AppModel
    let source: Source
    @State private var query = ""
    var body: some View {
        List {
            ForEach(model.libraryItems(selectedCategoryID: nil).filter { $0.manga.sourceID == source.id && (query.isEmpty || $0.manga.title.localizedCaseInsensitiveContains(query)) }) { item in
                NavigationLink { MigrationConfirmationView(source: source, target: item.manga) } label: {
                    MangaRow(manga: item.manga, hideSensitiveCover: model.state.securityPreferences.hideSensitiveCovers, allowsAdultContent: source.allowsAdultContent)
                }
            }
        }.searchable(text: $query).navigationTitle("Original title")
    }
}

struct MigrationConfirmationView: View {
    @EnvironmentObject private var model: AppModel
    let source: Source
    let target: Manga // Compatibility: existing callers pass the original library title.
    @State private var query = ""
    @State private var results: [MigrationCandidate] = []
    @State private var errors: [String] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var generation = UUID()
    var body: some View {
        List {
            Section("Original") { Text(target.title); Text(source.name).foregroundStyle(.secondary) }
            Section("Other sources") {
                if searching { ProgressView("Searching") }
                ForEach(results) { candidate in
                    NavigationLink { MigrationConfigView(source: candidate.source, target: candidate.manga, original: target) } label: {
                        MangaRow(manga: candidate.manga, hideSensitiveCover: model.state.securityPreferences.hideSensitiveCovers, allowsAdultContent: candidate.source.allowsAdultContent)
                    }
                }
                if !searching && results.isEmpty { Text("Submit a title to search enabled target sources.") }
                ForEach(errors, id: \.self) { Text($0).font(.footnote) }
            }
        }.searchable(text: $query).onAppear { query = target.title }
        .onSubmit(of: .search) { search() }
        .onChange(of: query) { _, _ in generation = UUID(); searchTask?.cancel(); searching = false }
        .onDisappear { generation = UUID(); searchTask?.cancel() }
        .navigationTitle("Choose target")
    }
    private func search() {
        searchTask?.cancel(); generation = UUID(); let token = generation, text = query
        results = []; errors = []; searching = true
        searchTask = Task { @MainActor in
            defer { if generation == token { searching = false } }
            for source in model.visibleSources where source.id != target.sourceID && model.supportsLiveSource(source) {
                do {
                    let items = try await model.searchSource(source, query: text)
                    guard !Task.isCancelled, generation == token else { return }
                    results.append(contentsOf: items.map { MigrationCandidate(id: $0.id, source: source, manga: $0) })
                } catch {
                    guard !Task.isCancelled, generation == token else { return }
                    errors.append(source.name + ": " + error.localizedDescription)
                }
            }
        }
    }
}

struct MigrationConfigView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let source: Source
    let target: Manga
    var original: Manga? = nil
    @State private var options = MigrationOptions()
    @State private var plan: MigrationPlan?
    @State private var message: String?
    @State private var confirming = false
    var body: some View {
        Form {
            Section("Target") { Text(target.title); Text(source.name) }
            Section("Transfer") {
                Toggle("Read status, bookmarks and resume", isOn: $options.reading)
                Toggle("Categories", isOn: $options.categories)
                Toggle("Local tracking records", isOn: $options.tracking)
                Toggle("History", isOn: $options.history)
                Toggle("Notes", isOn: $options.notes)
                Toggle("Remove original from Library", isOn: $options.removeOriginal)
            }
            if let plan {
                Section("Mapping") {
                    Text("\(plan.chapterMap.count) exact unique chapter numbers matched. \(plan.unmappedCount) missing or ambiguous chapters will remain unmapped.")
                    Text("Downloaded files remain with the original edition. Unknown target page counts resume at page one. Original timestamps are retained.")
                    Button("Apply Migration") { confirming = true }.disabled(model.state.securityPreferences.lockLibraryEdits)
                }
            } else if message == nil { ProgressView("Fetching target chapters") }
            if let message { Text(message) }
        }.navigationTitle("Transfer options")
        .task {
            guard let original else { message = "Choose an original library title first."; return }
            do { plan = try await model.prepareMigration(original: original, target: target) }
            catch { message = error.localizedDescription }
        }
        .confirmationDialog("Apply this migration?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Apply") { guard let plan else { return }; do { try model.applyMigration(plan, options: options); dismiss() } catch { message = error.localizedDescription } }
        }
    }
}
