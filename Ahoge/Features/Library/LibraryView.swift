// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var categoryID: String?
    @State private var search = ""
    @State private var sort: LibrarySortMode = .recent
    @State private var descending = true
    @State private var listDisplay = false
    @State private var preferencesLoaded = false
    @State private var downloaded: CollectionFilter = .any
    @State private var unread: CollectionFilter = .any
    @State private var bookmarked: CollectionFilter = .any
    @State private var completed: CollectionFilter = .any
    @State private var tracked: CollectionFilter = .any
    @State private var selected = Set<String>()
    @State private var selecting = false
    @State private var showCategories = false
    @State private var confirmRemove = false
    @State private var confirmDownload = false
    @State private var randomManga: Manga?
    private var items: [LibraryManga] {
        let values = model.libraryItems(selectedCategoryID: categoryID, searchText: search, sortMode: sort).filter { item in
            let chapters = model.chapters(for: item.manga)
            let states = chapters.map { model.chapterState(for: $0.id, mangaID: item.id) }
            return downloaded.matches(model.isTitleDownloaded(manga: item.manga)) && unread.matches(states.contains { !$0.isRead }) && bookmarked.matches(states.contains { $0.isBookmarked }) && completed.matches(!states.isEmpty && states.allSatisfy { $0.isRead }) && tracked.matches(!model.trackerBindings(for: item.manga).isEmpty)
        }
        if sort == .random { return values }
        let baseIsDescending = sort != .alphabetical
        return descending == baseIsDescending ? values : Array(values.reversed())
    }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    Color.clear.frame(height: 1).id("top")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            category("All", id: nil)
                            category("Uncategorized", id: "")
                            ForEach(model.categories) { category($0.name, id: $0.id) }
                        }.padding(.horizontal, 16)
                    }
                    if !model.libraryRefreshErrors.isEmpty {
                        VStack(alignment: .leading) { ForEach(model.libraryRefreshErrors.keys.sorted(), id: \.self) { id in Text(model.libraryRefreshErrors[id] ?? "").font(.caption).foregroundStyle(.secondary) } }.padding(.horizontal, 16)
                    }
                    if items.isEmpty {
                        ContentUnavailableView("No titles", systemImage: "books.vertical", description: Text("Add titles from Browse, or change your search and filters."))
                    } else {
                        LazyVGrid(columns: listDisplay || typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 108), spacing: 10)], spacing: 16) {
                            ForEach(items) { item in
                                Group {
                                    if selecting { Button { toggle(item.id) } label: { card(item).overlay(alignment: .topTrailing) { Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle").font(.title2).padding(4).foregroundStyle(.tint).background(.background, in: Circle()) } } }
                                    else { NavigationLink { MangaDetailView(manga: item.manga) } label: { card(item) } }
                                }.buttonStyle(.plain).contextMenu {
                                    Button("Select", systemImage: "checkmark.circle") { selecting = true; selected.insert(item.id) }
                                    if let chapter = model.startChapter(for: item.manga), model.canReadChapter(chapter, manga: item.manga) { NavigationLink("Start / Continue", destination: ReaderView(manga: item.manga, initialChapter: chapter)) }
                                }
                            }
                        }.padding(.horizontal, 16)
                    }
                }.padding(.bottom, 16)
            }.onReceive(NotificationCenter.default.publisher(for: .ahogeLibraryReselected)) { _ in proxy.scrollTo("top", anchor: .top) }
        }
        .navigationTitle(selecting ? "\(selected.count) selected" : "Library")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search library")
        .refreshable { await model.refreshLibrary(categoryID: categoryID) }
        .onAppear {
            guard !preferencesLoaded else { return }
            restorePreferences()
            preferencesLoaded = true
        }
        .onChange(of: model.state.libraryPreferences) { _, _ in restorePreferences() }
        .onChange(of: listDisplay) { _, value in if preferencesLoaded { model.setLibraryDisplayList(value) } }
        .onChange(of: descending) { _, value in if preferencesLoaded { model.setLibrarySortDescending(value) } }
        .onChange(of: downloaded) { _, value in persistFilter("downloaded", value) }
        .onChange(of: unread) { _, value in persistFilter("unread", value) }
        .onChange(of: bookmarked) { _, value in persistFilter("bookmarked", value) }
        .onChange(of: completed) { _, value in persistFilter("completed", value) }
        .onChange(of: tracked) { _, value in persistFilter("tracked", value) }
        .onChange(of: sort) { _, value in model.setLibrarySortMode(value) }
        .onChange(of: items.map(\.id)) { _, ids in selected.formIntersection(ids) }
        .sheet(isPresented: $showCategories) { CollectionCategoryPicker(mangaIDs: Array(selected)) }
        .navigationDestination(item: $randomManga) { MangaDetailView(manga: $0) }
        .confirmationDialog("Download chapters for \(selected.count) titles?", isPresented: $confirmDownload) {
            Button("Queue downloads") { for item in items where selected.contains(item.id) { model.enqueueDownloadAllChapters(manga: item.manga, chapters: model.chapters(for: item.manga)) } }
        } message: { Text("\(downloadCount) chapters will be considered; existing downloads are skipped.") }
        .confirmationDialog("Remove \(selected.count) titles from Library?", isPresented: $confirmRemove) {
            Button("Remove titles", role: .destructive) { for item in items where selected.contains(item.id) { model.toggleLibrary(item.manga) }; selected.removeAll(); selecting = false }
        } message: { Text("Downloads and history remain available.") }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Menu {
                Picker("Sort", selection: $sort) { ForEach(LibrarySortMode.allCases) { Text($0.title).tag($0) } }
                Toggle("Descending order", isOn: $descending).disabled(sort == .random)
                Toggle("List display", isOn: $listDisplay)
                CollectionFilterPicker(title: "Downloaded", value: $downloaded)
                CollectionFilterPicker(title: "Unread", value: $unread)
                CollectionFilterPicker(title: "Bookmarked", value: $bookmarked)
                CollectionFilterPicker(title: "Completed chapters", value: $completed)
                CollectionFilterPicker(title: "Local tracking", value: $tracked)
                Text("Display, direction and filters are saved for Library across all categories. Completed means every known chapter is read.")
                Button("Reset filters") { downloaded = .any; unread = .any; bookmarked = .any; completed = .any; tracked = .any }
                Button(selecting ? "Cancel selection" : "Select titles") { selecting.toggle(); selected.removeAll() }
                Button("Random title") { randomManga = items.randomElement()?.manga }.disabled(items.isEmpty)
                NavigationLink("Categories") { CategoryManagementView() }
                NavigationLink("Library Settings") { LibrarySettingsView() }
                NavigationLink("Migration") { LibraryBatchMigrationView() }
            } label: { Image(systemName: "slider.horizontal.3") } }
            if selecting {
                ToolbarItem(placement: .bottomBar) { Menu("Selection actions") {
                    Button("Select all") { selected = Set(items.map(\.id)) }
                    Button("Invert selection") { selected = Set(items.map(\.id)).subtracting(selected) }
                    Button("Categories") { showCategories = true }.disabled(selected.isEmpty || editsLocked)
                    NavigationLink("Migrate selected titles") { LibraryBatchMigrationView(mangaIDs: selected) }.disabled(selected.isEmpty || editsLocked)
                    Button("Mark read") { mark(true) }.disabled(selected.isEmpty || editsLocked)
                    Button("Mark unread") { mark(false) }.disabled(selected.isEmpty || editsLocked)
                    Button("Download chapters") { confirmDownload = true }.disabled(selected.isEmpty)
                    Button("Remove from Library", role: .destructive) { confirmRemove = true }.disabled(selected.isEmpty || editsLocked)
                } }
            }
        }
    }
    private func restorePreferences() {
        let preferences = model.state.libraryPreferences
        sort = preferences.sortMode
        listDisplay = preferences.displayList
        descending = preferences.sortDescending
        downloaded = savedFilter("downloaded")
        unread = savedFilter("unread")
        bookmarked = savedFilter("bookmarked")
        completed = savedFilter("completed")
        tracked = savedFilter("tracked")
    }
    private var editsLocked: Bool { model.state.securityPreferences.lockLibraryEdits }
    private func savedFilter(_ key: String) -> CollectionFilter {
        guard let stored = model.state.libraryPreferences.filters[key], let value = Int(stored) else { return .any }
        return CollectionFilter(rawValue: value) ?? .any
    }
    private func persistFilter(_ key: String, _ value: CollectionFilter) {
        if preferencesLoaded { model.setLibraryFilter(key, value: String(value.rawValue)) }
    }
    private var downloadCount: Int {
        items.filter { selected.contains($0.id) }.reduce(0) { count, item in count + model.chapters(for: item.manga).filter { !model.isChapterDownloaded(manga: item.manga, chapter: $0) }.count }
    }
    private func category(_ title: String, id: String?) -> some View { Button(title) { categoryID = id }.buttonStyle(.bordered).tint(categoryID == id ? .accentColor : .secondary) }
    private func toggle(_ id: String) { if !selected.insert(id).inserted { selected.remove(id) } }
    private func mark(_ read: Bool) { for item in items where selected.contains(item.id) { model.setChaptersRead(model.chapters(for: item.manga).map(\.id), mangaID: item.id, read: read) } }
    private func card(_ item: LibraryManga) -> some View {
        let count = model.chapters(for: item.manga).filter { !model.chapterState(for: $0.id, mangaID: item.id).isRead }.count
        return Group {
            if listDisplay || typeSize.isAccessibilitySize { MangaRow(manga: item.manga, hideSensitiveCover: model.state.securityPreferences.hideSensitiveCovers, allowsAdultContent: model.source(for: item.manga.sourceID)?.allowsAdultContent ?? false) }
            else { AhogeMangaGridCard(manga: item.manga, hideSensitiveCover: model.state.securityPreferences.hideSensitiveCovers, allowsAdultContent: model.source(for: item.manga.sourceID)?.allowsAdultContent ?? false, badgeText: model.state.libraryPreferences.showUnreadBadge && count > 0 ? "\(count)" : nil, showsDownloadedBadge: model.state.libraryPreferences.showDownloadedBadge && model.isTitleDownloaded(manga: item.manga)) }
        }
    }
}
