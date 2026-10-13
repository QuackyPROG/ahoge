// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI
import UniformTypeIdentifiers

struct BrowseView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var sourceColumns: [GridItem] {
        [GridItem(.flexible(), alignment: .leading)]
    }

    private var discoverySources: [Source] {
        model.visibleSources.filter { !model.mangas(for: $0).isEmpty }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AhogeLayout.sectionSpacing) {
                NavigationLink {
                    GlobalSearchView()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "magnifyingglass")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.tint)
                            .frame(width: 42, height: 42)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Search across sources")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Find manga by title, author, or genre")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(AhogePalette.surface, in: RoundedRectangle(cornerRadius: AhogeLayout.cardRadius, style: .continuous))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 16) {
                    Text("On the shelves")
                        .font(.title2.weight(.bold))
                    Text("Titles already available from your sources")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if discoverySources.isEmpty {
                        ContentUnavailableView("Discover your next read", systemImage: "books.vertical", description: Text("Open a source below to browse its catalog. Available titles will appear here."))
                    } else {
                        ForEach(discoverySources.prefix(3)) { source in
                            VStack(alignment: .leading, spacing: 12) {
                                NavigationLink { SourceView(source: source) } label: {
                                    Label(source.name, systemImage: source.systemImage)
                                        .font(.headline).frame(minHeight: 44)
                                }
                                LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 132), spacing: 16)], alignment: .leading, spacing: 20) {
                                    ForEach(model.mangas(for: source).prefix(4)) { manga in
                                        NavigationLink { MangaDetailView(manga: manga) } label: {
                                            AhogeMangaGridCard(manga: manga, hideSensitiveCover: model.state.securityPreferences.hideSensitiveCovers, allowsAdultContent: source.allowsAdultContent, badgeText: source.name)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }

                if !model.visibleSources.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        AhogeSectionHeader("Quick sources", subtitle: "Jump straight into a catalog") {
                            NavigationLink("All Sources") { SourcesView() }
                                .font(.subheadline.weight(.semibold))
                        }

                        LazyVGrid(columns: sourceColumns, alignment: .leading, spacing: 12) {
                            ForEach(model.visibleSources.prefix(6)) { source in
                                NavigationLink {
                                    SourceView(source: source)
                                } label: {
                                    SourceRow(source: source)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No sources available",
                        systemImage: "globe.badge.chevron.backward",
                        description: Text("Review the source catalog and filters to make sources available.")
                    )
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 12) {
                    AhogeSectionHeader("Manage discovery", subtitle: "Choose catalogs and organize your sources")
                    VStack(spacing: 0) {
                        NavigationLink {
                            SourcesView()
                        } label: {
                            AhogeActionRow(title: "Sources", subtitle: "Browse and filter enabled sources", systemImage: "globe")
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 56)

                        NavigationLink {
                            SourceCatalogView()
                        } label: {
                            AhogeActionRow(title: "Source Catalog", subtitle: "Install and manage source definitions", systemImage: "shippingbox")
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 56)

                        NavigationLink {
                            MigrationSourcesView()
                        } label: {
                            AhogeActionRow(title: "Migration", subtitle: "Move library titles between sources", systemImage: "arrow.triangle.swap")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, AhogeLayout.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Explore")
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
                Section {
                    ForEach(filteredSources) { source in
                        NavigationLink { SourceView(source: source) } label: {
                            SourceRow(source: source)
                        }
                    }
                } header: { Text("Available catalogs") } footer: {
                    Text("Source filters control language, visibility, and enabled or pinned sources.")
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
    @State private var feedKind: SourceFeedKind = .popular
    @State private var showingFilters = false
    @State private var isLoading = false
    @State private var runtimeManga: [Manga] = []
    @State private var sortValue = "popular"
    @State private var orderAscending = false
    @State private var selectedTypes: Set<String> = []
    @State private var includedGenres: Set<String> = []
    @State private var excludedGenres: Set<String> = []

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
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
                }

                if isLoading {
                    loadingGrid
                } else if let error = model.sourceError(for: source.id), displayedManga.isEmpty {
                    ContentUnavailableView(
                        "Source unavailable",
                        systemImage: "wifi.exclamationmark",
                        description: Text(error)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
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
                            mangaGridLink(for: manga)
                        }
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
            Task { await reloadRuntimeFeed() }
        }
        .onSubmit(of: .search) {
            guard model.supportsLiveSource(source) else { return }
            Task { await reloadRuntimeFeed() }
        }
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
                    genres: model.genreTags(for: source.id)
                )
            }
            .presentationDetents([.medium, .large])
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if model.supportsLiveSource(source) {
                    Button {
                        showingFilters = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Runtime filters")
                }

                Menu {
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

    private func reloadRuntimeFeed() async {
        isLoading = true
        let filters: [SourceFilterValue] = [
            .sort(feedKind == .latest ? "updated" : sortValue),
            .orderAscending(orderAscending),
            .types(Array(selectedTypes).sorted()),
            .genreInclude(mode: "OR", slugs: Array(includedGenres).sorted()),
            .genreExclude(mode: "OR", slugs: Array(excludedGenres).sorted()),
        ]
        let effectiveQuery = feedKind == .search ? query : ""
        await model.refreshSourceFeed(for: source, mode: feedKind, query: effectiveQuery, filters: filters)
        runtimeManga = model.mangas(for: source)
        isLoading = false
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

    private let typeOptions = ["manga", "manhwa", "manhua"]
    private let sortOptions: [(String, String)] = [
        ("Popular", "popular"),
        ("Rating", "rating"),
        ("Updated", "updated"),
        ("Bookmarked", "bookmarked"),
        ("Title", "title"),
    ]

    var body: some View {
        Form {
            Section {
                Picker("Sort by", selection: $sortValue) {
                    ForEach(sortOptions, id: \.1) { option in
                        Text(option.0).tag(option.1)
                    }
                }
                Toggle("Ascending", isOn: $orderAscending)
            } header: { Text("Ordering") } footer: { Text("Filters apply with the next feed request or search.") }

            Section("Type") {
                ForEach(typeOptions, id: \.self) { option in
                    Toggle(option.capitalized, isOn: binding(for: option, in: $selectedTypes))
                }
            }

            if !genres.isEmpty {
                Section("Include Genres") {
                    ForEach(genres.prefix(12)) { genre in
                        Toggle(genre.name, isOn: binding(for: genre.slug, in: $includedGenres))
                    }
                }

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
