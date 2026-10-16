// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI
import UniformTypeIdentifiers

struct BrowseView: View {
    @EnvironmentObject private var model: AppModel
    @State private var section = 0
    @State private var showingSearch = false
    var body: some View {
        VStack(spacing: 0) {
            Picker("Browse section", selection: $section) {
                Text("Sources").tag(0); Text("Extensions").tag(1); Text("Migrate").tag(2)
            }.pickerStyle(.segmented).padding(.horizontal)
            Group {
                switch section {
                case 1: SourceCatalogView()
                case 2: MigrationSourcesView()
                default: SourcesView()
                }
            }
        }
        .navigationTitle("Browse")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingSearch = true } label: { Label("Global search", systemImage: "magnifyingglass") } } }
        .onReceive(NotificationCenter.default.publisher(for: .ahogeBrowseReselected)) { _ in showingSearch = true }
        .sheet(isPresented: $showingSearch) { NavigationStack { GlobalSearchView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showingSearch = false } } } } }
    }
}

struct SourcesView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var query = ""

    private var filteredSources: [Source] {
        model.visibleSources.filter { source in
            query.isEmpty || source.name.localizedCaseInsensitiveContains(query) || source.summary.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            if filteredSources.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ForEach(SourceLanguage.allCases) { language in
                    let grouped = filteredSources.filter { $0.language == language }.sorted { lhs, rhs in
                        let left = model.sourceIsPinned(lhs), right = model.sourceIsPinned(rhs)
                        return left == right ? lhs.name < rhs.name : left
                    }
                    if !grouped.isEmpty {
                        Section(language.rawValue) {
                            ForEach(grouped) { source in
                                NavigationLink { SourceView(source: source) } label: { SourceRow(source: source) }
                                .contextMenu {
                                    Button(model.sourceIsPinned(source) ? "Unpin" : "Pin") { model.setSourcePinned(source, pinned: !model.sourceIsPinned(source)) }
                                    Button(model.sourceIsEnabled(source) ? "Disable" : "Enable") { model.setSourceEnabled(source, enabled: !model.sourceIsEnabled(source)) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: "Find source")
        .navigationTitle("Sources")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SourcesFilterView()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Source filters")
            }
        }
    }
}

struct SourceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let source: Source
    @State private var query = ""
    @State private var showingImporter = false
    @State private var listDisplay = false
    @State private var feedKind: SourceFeedKind = .popular
    @State private var showingFilters = false
    @State private var runtimeManga: [Manga] = []
    @State private var feedSession = SourceFeedSession()
    private var isLoading: Bool { feedSession.isLoading }
    private var reachedEnd: Bool { feedSession.reachedEnd }
    @State private var feedTask: Task<Void, Never>?
    @State private var feedError: String?
    @State private var sortValue = ""
    @State private var orderAscending = false
    @State private var selectedTypes: Set<String> = []
    @State private var includedGenres: Set<String> = []
    @State private var excludedGenres: Set<String> = []

    private var columns: [GridItem] {
        (dynamicTypeSize.isAccessibilitySize || listDisplay)
            ? [GridItem(.flexible(), alignment: .top)]
            : [GridItem(.adaptive(minimum: 132), spacing: 16, alignment: .top)]
    }

    private var filteredManga: [Manga] {
        let items = model.mangas(for: source)
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.author.localizedCaseInsensitiveContains(query) ||
            $0.genres.joined(separator: " ").localizedCaseInsensitiveContains(query)
        }
    }

    private var displayedManga: [Manga] {
        model.supportsLiveSource(source) ? runtimeManga : filteredManga
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                sourceHeader

                if model.supportsLiveSource(source) {
                    Picker("Feed", selection: $feedKind) {
                        ForEach(SourceFeedKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minHeight: 44)
                    if feedKind != .search {
                        Button("Search with filters") { feedKind = .search }
                        Text("Popular and Latest use the source's fixed ordering. Filters apply in Search when supported.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if !searchFilters.allowsPagination {
                        Text("This link looks up one title directly. Filters and additional pages do not apply.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if !searchFilters.isAvailable {
                        Text("This source's text search does not support editable filters.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if isLoading && displayedManga.isEmpty {
                    loadingGrid
                } else if let error = feedError ?? model.sourceError(for: source.id), displayedManga.isEmpty {
                    ContentUnavailableView(
                        "Source unavailable",
                        systemImage: "wifi.exclamationmark",
                        description: Text(error)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                    Button("Retry") { startReload() }
                } else if model.supportsLiveSource(source) && feedKind == .search && feedSession.descriptor == nil {
                    ContentUnavailableView("Submit search", systemImage: "magnifyingglass",
                        description: Text("Submit the search field to load this query from page one."))
                } else if displayedManga.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty ? "No titles available" : "No results",
                        systemImage: "books.vertical",
                        description: Text(query.isEmpty ? "This source did not return any titles for the selected feed." : "Try another search or adjust filters.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(displayedManga) { manga in
                            if listDisplay { NavigationLink { MangaDetailView(manga: manga) } label: { MangaRow(manga: manga, hideSensitiveCover: model.state.securityPreferences.hideSensitiveCovers, allowsAdultContent: source.allowsAdultContent) } } else { mangaGridLink(for: manga) }
                        }
                    }
                    if model.supportsLiveSource(source) && !reachedEnd {
                        Button(isLoading ? "Loading..." : "Load more") { loadNextPage() }.disabled(isLoading)
                    }
                    if let feedError { Label(feedError, systemImage: "exclamationmark.triangle")
                        Button("Retry") { if runtimeManga.isEmpty { startReload() } else { loadNextPage() } }

                    }
                }
            }
            .padding(.horizontal, AhogeLayout.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .searchable(text: $query, prompt: "Search \(source.name)")
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard model.supportsLiveSource(source) else { return }
            await model.loadGenreTags(for: source)
            await reloadRuntimeFeed()
        }
        .onChange(of: feedKind) { _, _ in
            guard model.supportsLiveSource(source) else { return }
            showingFilters = false
            startReload()
        }
        .onSubmit(of: .search) {
            guard model.supportsLiveSource(source) else { return }
            if feedKind != .search { feedKind = .search }
            else { startReload() }
        }
        .onChange(of: query) { _, _ in
            guard model.supportsLiveSource(source), feedKind == .search else { return }
            showingFilters = false
            invalidateFeed()
        }
        .onChange(of: selectedRuntimeFilters) { _, _ in
            guard model.supportsLiveSource(source), feedKind == .search, searchFilters.isAvailable else { return }
            startReload()
        }
        .onDisappear { invalidateFeed() }
        .refreshable { await reloadRuntimeFeed() }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.folder, .image, .zip, .ahogeCBZ, .ahogeEPUB],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                model.importItems(from: urls)
            }
        }
        .sheet(isPresented: $showingFilters) {
            NavigationStack {
                RuntimeSourceFiltersView(
                    sortValue: $sortValue,
                    orderAscending: $orderAscending,
                    selectedTypes: $selectedTypes,
                    includedGenres: $includedGenres,
                    excludedGenres: $excludedGenres,
                    genres: model.genreTags(for: source.id),
                    supported: searchFilters
                )
            }
            .presentationDetents([.medium, .large])
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if model.supportsLiveSource(source) && feedKind == .search && searchFilters.isAvailable {
                    Button {
                        showingFilters = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Runtime filters")
                }

                Menu {
                    Toggle("List display", isOn: $listDisplay)
                    NavigationLink {
                        SourcePreferencesView(source: source)
                    } label: {
                        Label("Source Preferences", systemImage: "slider.horizontal.3")
                    }

                    NavigationLink {
                        SourceWebView(source: source)
                    } label: {
                        Label("Open Source Website", systemImage: "safari")
                    }

                    if source.kind == .local {
                        Button {
                            showingImporter = true
                        } label: {
                            Label("Import Local Files", systemImage: "square.and.arrow.down")
                        }

                        NavigationLink {
                            LocalImportsView()
                        } label: {
                            Label("Local Imports", systemImage: "internaldrive")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Source actions")
            }
        }
    }

    private var sourceHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: source.systemImage)
                .font(.title2.weight(.semibold))
                .frame(width: 48, height: 48)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(source.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 7) {
                    AhogeStatusBadge(title: source.language.rawValue, systemImage: "character.bubble")
                    AhogeStatusBadge(title: source.kind == .local ? "Local" : "Remote", systemImage: source.kind == .local ? "internaldrive" : "network")
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var loadingGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
            ForEach(0..<8, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 9) {
                    RoundedRectangle(cornerRadius: AhogeLayout.coverRadius, style: .continuous)
                        .fill(Color.secondary.opacity(0.10))
                        .aspectRatio(AhogeLayout.compactCoverRatio, contentMode: .fit)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.10))
                        .frame(height: 15)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.08))
                        .frame(width: 90, height: 11)
                }
                .redacted(reason: .placeholder)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading manga")
    }

    private func mangaGridLink(for manga: Manga) -> some View {
        let isInLibrary = model.isInLibrary(manga)
        return NavigationLink {
            MangaDetailView(manga: manga)
        } label: {
            AhogeMangaGridCard(
                manga: manga,
                hideSensitiveCover: model.state.securityPreferences.hideSensitiveCovers,
                allowsAdultContent: model.source(for: manga.sourceID)?.allowsAdultContent ?? false,
                badgeText: isInLibrary ? "Library" : nil
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                model.toggleLibrary(manga)
            } label: {
                Label(isInLibrary ? "Remove from Library" : "Add to Library", systemImage: isInLibrary ? "bookmark.slash" : "bookmark")
            }
        }
    }

    private var runtimeFilters: [SourceFilterValue] {
        guard feedKind == .search else { return [] }
        return searchFilters.applying(selectedRuntimeFilters)
    }

    private var selectedRuntimeFilters: [SourceFilterValue] {
        [.sort(sortValue), .orderAscending(orderAscending),
         .types(Array(selectedTypes).sorted()), .genreInclude(mode: "OR", slugs: Array(includedGenres).sorted()),
         .genreExclude(mode: "OR", slugs: Array(excludedGenres).sorted())]
    }

    private var searchFilters: SourceSearchFilters {
        let descriptor = model.descriptor(for: source.id)
        return SourceSearchFilters.supported(family: descriptor?.engineFamily,
            adapter: descriptor?.overrides["adapter"], query: query, baseURL: descriptor?.context?.baseURL)
    }

    private var submittedDescriptor: SourceFeedDescriptor {
        SourceFeedDescriptor(sourceID: source.id, mode: feedKind,
            query: feedKind == .search ? query : "", filters: runtimeFilters,
            allowsPagination: feedKind != .search || searchFilters.allowsPagination)
    }

    private func invalidateFeed() {
        feedTask?.cancel(); feedSession.invalidate()
        runtimeManga = []; feedError = nil
    }

    private func beginReload() -> SourceFeedSession.Request {
        invalidateFeed()
        return feedSession.begin(submittedDescriptor)
    }

    private func startReload() {
        // Reset synchronously, before the new task can yield or Load more can run.
        let request = beginReload()
        feedTask = Task { await performFeedRequest(request) }
    }

    private func reloadRuntimeFeed() async {
        let request = beginReload()
        await performFeedRequest(request)
    }

    private func loadNextPage() {
        guard let request = feedSession.nextRequest() else { return }
        feedError = nil
        feedTask = Task { await performFeedRequest(request) }
    }

    private func performFeedRequest(_ request: SourceFeedSession.Request) async {
        let descriptor = request.descriptor
        do {
            let items = try await model.sourceFeed(source, mode: descriptor.mode, query: descriptor.query,
                filters: descriptor.filters, page: request.page)
            guard !Task.isCancelled, feedSession.accepts(request) else { return }
            var ids = Set(runtimeManga.map(\.id))
            let added = items.filter { ids.insert($0.id).inserted }
            runtimeManga.append(contentsOf: added)
            feedSession.finish(request, addedCount: added.count)
            model.setCachedSourceManga(runtimeManga, for: descriptor.sourceID)
        } catch {
            guard !Task.isCancelled, feedSession.accepts(request) else { return }
            feedSession.fail(request); feedError = error.localizedDescription
        }
    }

}

struct SourcesFilterView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Languages") {
                ForEach(SourceLanguage.allCases) { language in
                    Toggle(language.rawValue, isOn: Binding(
                        get: { model.state.browsePreferences.enabledLanguages.contains(language) },
                        set: { model.setBrowseLanguage(language, enabled: $0) }
                    ))
                }
            }

            Section {
                Toggle("Hide adult sources", isOn: Binding(
                    get: { model.state.browsePreferences.hideAdultSources },
                    set: model.setHideAdultSources
                ))
                Toggle("Enabled only", isOn: Binding(
                    get: { model.state.browsePreferences.enabledSourcesOnly },
                    set: model.setEnabledSourcesOnly
                ))
                Toggle("Pinned only", isOn: Binding(
                    get: { model.state.browsePreferences.pinnedSourcesOnly },
                    set: model.setPinnedSourcesOnly
                ))
            } header: { Text("Visibility") } footer: { Text("These choices control which sources appear in Explore and search.") }
        }
        .navigationTitle("Source Filters")
    }
}

struct SourceRow: View {
    let source: Source

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: source.systemImage)
                .font(.title3).foregroundStyle(.tint)
                .frame(width: 32, height: 44).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(source.name).font(.headline)
                Text(source.summary).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(source.language.rawValue) · \(source.kind == .local ? "Local" : "Remote")")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 8)
    }
}

private struct RuntimeSourceFiltersView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var sortValue: String
    @Binding var orderAscending: Bool
    @Binding var selectedTypes: Set<String>
    @Binding var includedGenres: Set<String>
    @Binding var excludedGenres: Set<String>
    let genres: [GenreTag]
    let supported: SourceSearchFilters

    private let typeOptions = ["manga", "manhwa", "manhua"]

    var body: some View {
        Form {
            Section {
                if !supported.sorts.isEmpty {
                    Picker("Sort by", selection: $sortValue) {
                        Text("Source default").tag("")
                        ForEach(supported.sorts, id: \.self) { option in
                            Text(option.replacingOccurrences(of: "_", with: " ").capitalized).tag(option)
                        }
                    }
                }
                if supported.ascending { Toggle("Ascending", isOn: $orderAscending) }
            } header: { Text("Search ordering") } footer: { Text("Changing a supported filter starts Search from page one. Other filter kinds are unavailable for this source.") }

            if supported.types {
                Section("Type") {
                    ForEach(typeOptions, id: \.self) { option in
                        Toggle(option.capitalized, isOn: binding(for: option, in: $selectedTypes))
                    }
                }
            }

            if supported.includeGenres && !genres.isEmpty {
                Section("Include Genres") {
                    ForEach(genres.prefix(12)) { genre in
                        Toggle(genre.name, isOn: binding(for: genre.slug, in: $includedGenres))
                    }
                }

            }
            if supported.excludeGenres && !genres.isEmpty {
                Section("Exclude Genres") {
                    ForEach(genres.prefix(12)) { genre in
                        Toggle(genre.name, isOn: binding(for: genre.slug, in: $excludedGenres))
                    }
                }
            }
        }
        .navigationTitle("Filters")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func binding(for value: String, in set: Binding<Set<String>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(value) },
            set: { enabled in
                if enabled { set.wrappedValue.insert(value) }
                else { set.wrappedValue.remove(value) }
            }
        )
    }
}

struct MangaRow: View {
    let manga: Manga
    let hideSensitiveCover: Bool
    let allowsAdultContent: Bool

    init(manga: Manga, hideSensitiveCover: Bool = false, allowsAdultContent: Bool = false) {
        self.manga = manga
        self.hideSensitiveCover = hideSensitiveCover
        self.allowsAdultContent = allowsAdultContent
    }

    var body: some View {
        HStack(spacing: 14) {
            MangaCoverView(
                manga: manga,
                hideSensitiveCover: hideSensitiveCover,
                allowsAdultContent: allowsAdultContent,
                cornerRadius: 8,
                overlaySystemImage: "book.closed.fill"
            )
            .frame(width: 56, height: 80)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(manga.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                Text(manga.author).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(manga.statusText).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct LocalImportsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingImporter = false

    var body: some View {
        List {
            Section {
                Label("Your offline collection", systemImage: "internaldrive")
                    .font(.title3.weight(.semibold))
                Text(model.localImportSummary())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    showingImporter = true
                } label: {
                    Label("Import from Files", systemImage: "square.and.arrow.down")
                }
            }

            if !model.importedJobs().isEmpty {
                Section("Import Jobs") {
                    ForEach(model.importedJobs()) { job in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(job.fileName).font(.headline)
                            Text("\(job.kind.rawValue.uppercased()) • \(job.status.rawValue)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(job.detail).font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            Section("Imported Titles") {
                if let localSource = model.primaryLocalSource() {
                    let importedTitles = model.mangas(for: localSource)
                    if importedTitles.isEmpty {
                        ContentUnavailableView("No imported titles yet", systemImage: "books.vertical", description: Text("Use Import from Files to add chapters stored on this device."))
                    }
                    ForEach(importedTitles) { manga in
                        NavigationLink {
                            MangaDetailView(manga: manga)
                        } label: {
                            MangaRow(
                                manga: manga,
                                hideSensitiveCover: model.state.securityPreferences.hideSensitiveCovers,
                                allowsAdultContent: model.source(for: manga.sourceID)?.allowsAdultContent ?? false
                            )
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Local source unavailable",
                        systemImage: "externaldrive.badge.exclamationmark",
                        description: Text("Restart the app or refresh sources before opening imported titles.")
                    )
                }
            }
        }
        .navigationTitle("Local Imports")
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.folder, .image, .zip, .ahogeCBZ, .ahogeEPUB],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result { model.importItems(from: urls) }
        }
    }
}
