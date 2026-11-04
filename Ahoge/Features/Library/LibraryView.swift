import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var sources: SourceManager
    @EnvironmentObject private var repo: LibraryRepository
    @EnvironmentObject private var updater: LibraryUpdater
    @EnvironmentObject private var downloads: DownloadManager
    @AppStorage(Pref.librarySort.name) private var storedSort = "title:asc"
    @AppStorage(Pref.libraryFilters.name) private var storedFilters = ""
    @AppStorage(Pref.perCategorySort.name) private var perCategorySort = false
    @AppStorage(Pref.libraryDefaultShelfSort.name) private var defaultShelfSort = ""
    @AppStorage(Pref.libraryDisplayMode.name) private var displayMode = "compact"
    @AppStorage(Pref.libraryColumnsPortrait.name) private var columnsPortrait = 0
    @AppStorage(Pref.libraryColumnsLandscape.name) private var columnsLandscape = 0
    @AppStorage(Pref.libraryBadgeUnread.name) private var badgeUnread = true
    @AppStorage(Pref.libraryBadgeDownloaded.name) private var badgeDownloaded = false
    @AppStorage(Pref.libraryBadgeLanguage.name) private var badgeLanguage = false
    @AppStorage(Pref.libraryBadgeLocal.name) private var badgeLocal = false
    @AppStorage(Pref.libraryShowCategoryTabs.name) private var showTabs = true
    @AppStorage(Pref.libraryShowItemCount.name) private var showCount = true
    @AppStorage(Pref.libraryShelf.name) private var shelf = 0
    @AppStorage(Pref.libraryContinueButton.name) private var continueButton = false
    @AppStorage(Pref.downloadedOnly.name) private var downloadedOnly = false
    @State private var path: [Route] = []
    @EnvironmentObject private var navigator: AppNavigator
    @State private var reading: (manga: LibraryManga, chapter: ChapterRecord)?
    @State private var search = ""
    @State private var selecting = false
    @State private var selection = Set<String>()
    @State private var settingCategories = false
    @State private var showingSheet = false
    @State private var landscape = false
    @State private var confirmRemove = false
    @State private var confirmDeleteDownloads = false
    @State private var removedWithDownloads: [LibraryManga] = []
    /// Fixed while the screen lives, so "Random" sorts the same way on every redraw.
    @State private var randomSeed = UInt64.random(in: 0...UInt64.max)

    /// One pass over the library: titles per shelf (0 = in no category) with and without the search,
    /// filters and sort, the shelf list and the current shelf.
    private struct Snapshot {
        let buckets: [Int: [LibraryManga]]
        let items: [Int: [LibraryManga]]
        let shelves: [LibraryShelf]
        let currentId: Int
    }

    private var filters: LibraryFilters { LibraryFilters(stored: storedFilters) }

    private func snapshot() -> Snapshot {
        var buckets: [Int: [LibraryManga]] = [:]
        for title in repo.library where !downloadedOnly || downloads.downloadedCount(mangaKey: title.key) > 0 {
            let ids = repo.categoryIds(of: title)
            if ids.isEmpty {
                buckets[0, default: []].append(title)
            } else {
                for id in ids { buckets[Int(id), default: []].append(title) }
            }
        }
        // Default (titles in no category) when it has any or there are no categories, then each category.
        var shelves = repo.categories.map { LibraryShelf(id: Int($0.id), name: $0.name) }
        if shelves.isEmpty || !(buckets[0] ?? []).isEmpty {
            shelves.insert(LibraryShelf(id: 0, name: "Default"), at: 0)
        }
        let currentId = shelves.contains { $0.id == shelf } ? shelf : shelves.first?.id ?? 0
        let facts = LibraryFacts(downloadedCount: { downloads.downloadedCount(mangaKey: $0) }, randomSeed: randomSeed)
        var items: [Int: [LibraryManga]] = [:]
        for item in shelves {
            let sort = LibrarySort.effective(global: storedSort, perCategory: perCategorySort, shelfId: item.id, defaultShelf: defaultShelfSort, categories: repo.categories)
            items[item.id] = LibraryQuery(search: search, filters: filters, sort: sort).apply(to: buckets[item.id] ?? [], facts: facts)
        }
        return Snapshot(buckets: buckets, items: items, shelves: shelves, currentId: currentId)
    }

    private var selectedManga: [LibraryManga] { repo.library.filter { selection.contains($0.key) } }

    var body: some View {
        let snap = snapshot()
        let shelves = snap.shelves
        let currentId = snap.currentId
        let current = Binding(get: { currentId }, set: { shelf = $0 })
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if showTabs, shelves.count > 1 {
                    CategoryTabBar(
                        shelves: shelves,
                        counts: showCount ? Dictionary(uniqueKeysWithValues: shelves.map { ($0.id, (snap.items[$0.id] ?? []).count) }) : [:],
                        selection: current
                    )
                }
                TabView(selection: current) {
                    ForEach(shelves) { item in
                        page(item, titles: snap.buckets[item.id] ?? [], items: snap.items[item.id] ?? []).tag(item.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .id(shelves.map { $0.id })
            }
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { landscape = geometry.size.width > geometry.size.height }
                        .onChange(of: geometry.size) { _, size in landscape = size.width > size.height }
                }
            }
            .navigationTitle(selecting ? "\(selection.count) selected" : "Library")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search)
            .toolbar { toolbar(snap) }
            .safeAreaInset(edge: .bottom) { if selecting { selectionBar } }
            .overlay(alignment: .bottom) {
                if updater.isRunning, !selecting {
                    Label("Updating library… \(updater.done)/\(updater.total)", systemImage: "arrow.clockwise")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: updater.isRunning)
            .sheet(isPresented: $settingCategories) { SetCategoriesSheet(manga: selectedManga, onSave: endSelection) }
            .sheet(isPresented: $showingSheet) {
                LibrarySheet(shelfId: currentId, shelfName: shelves.first { $0.id == currentId }?.name ?? "Default")
            }
            .confirmationDialog(selection.count == 1 ? "Remove 1 title from your library?" : "Remove \(selection.count) titles from your library?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    let removed = selectedManga
                    for manga in removed { repo.setInLibrary(manga, false) }
                    removedWithDownloads = removed.filter { downloads.downloadedCount(mangaKey: $0.key) > 0 }
                    endSelection()
                }
            }
            .confirmationDialog("Delete downloads of \(selection.count) selected \(selection.count == 1 ? "title" : "titles")?", isPresented: $confirmDeleteDownloads, titleVisibility: .visible) {
                Button("Delete downloads", role: .destructive) {
                    downloads.delete(selectedManga.flatMap(\.chapters))
                    endSelection()
                }
            }
            .alert("Delete downloaded chapters?", isPresented: Binding(get: { !removedWithDownloads.isEmpty }, set: { if !$0 { removedWithDownloads = [] } })) {
                Button("Delete", role: .destructive) { downloads.delete(removedWithDownloads.flatMap(\.chapters)) }
                Button("Keep", role: .cancel) {}
            } message: {
                Text("These titles are no longer in your library.")
            }
            .fullScreenCover(isPresented: Binding(get: { reading != nil }, set: { if !$0 { reading = nil } })) {
                if let reading { ReaderView(sourceId: reading.manga.sourceId, manga: reading.manga, chapter: reading.chapter) }
            }
            .themedScreen()
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
            // A notification tap (or deep link) asked to show a screen.
            .onChange(of: navigator.pendingRoute, initial: true) { _, route in
                guard let route else { return }
                navigator.pendingRoute = nil
                path = [route]
            }
        }
    }

    private func page(_ shelf: LibraryShelf, titles: [LibraryManga], items: [LibraryManga]) -> some View {
        let unread = Dictionary(items.map { ($0.key, $0.unreadCount) }, uniquingKeysWith: { first, _ in first })
        let onContinue: ((MangaRef) -> Void)? = continueButton ? { ref in
            if let manga = repo.manga(sourceId: ref.sourceId, url: ref.url), let chapter = manga.nextUnreadChapter {
                reading = (manga, chapter)
            }
        } : nil
        let mode = LibraryDisplayMode(rawValue: displayMode) ?? .compact
        return ScrollView {
            if items.isEmpty { emptyState(shelf).padding(.top, 80) }
            MangaGrid(
                items: items.map(\.ref),
                selection: selecting ? $selection : nil,
                librarySelect: { startSelecting($0) },
                onContinue: onContinue,
                canContinue: { (unread[LibraryManga.makeKey(sourceId: $0.sourceId, url: $0.url)] ?? 0) > 0 },
                mode: mode,
                columns: landscape ? columnsLandscape : columnsPortrait,
                leadingBadges: { ref in leadingBadges(ref, unread: unread) },
                trailingBadges: { ref in trailingBadges(ref) }
            )
            .padding(.vertical, 8)
        }
        // Mihon refreshes the category on screen.
        .refreshable { await updater.update(titles, repo: repo, sources: sources) }
    }

    private func leadingBadges(_ ref: MangaRef, unread: [String: Int]) -> [CardBadge] {
        let key = LibraryManga.makeKey(sourceId: ref.sourceId, url: ref.url)
        var badges: [CardBadge] = []
        if badgeUnread, let count = unread[key], count > 0 { badges.append(CardBadge(text: "\(count)", kind: .unread)) }
        if badgeDownloaded {
            let count = downloads.downloadedCount(mangaKey: key)
            if count > 0 { badges.append(CardBadge(text: "\(count)", kind: .downloaded)) }
        }
        return badges
    }

    private func trailingBadges(_ ref: MangaRef) -> [CardBadge] {
        var badges: [CardBadge] = []
        if badgeLocal, ref.sourceId == LibraryBadges.localSourceId { badges.append(CardBadge(text: "Local", kind: .info)) }
        if badgeLanguage, let lang = sources.installed(ref.sourceId)?.lang { badges.append(CardBadge(text: lang.uppercased(), kind: .info)) }
        return badges
    }

    @ViewBuilder
    private func emptyState(_ shelf: LibraryShelf) -> some View {
        if repo.library.isEmpty {
            ContentUnavailableView("Your library is empty", systemImage: "books.vertical", description: Text("Add manga from Browse."))
        } else if !search.isEmpty {
            VStack(spacing: 16) {
                ContentUnavailableView.search(text: search)
                NavigationLink(value: Route.globalSearch(search)) {
                    Label("Search globally", systemImage: "globe")
                }
                .buttonStyle(.bordered)
            }
        } else if filters.isActive {
            ContentUnavailableView("No titles match the filters", systemImage: "line.3.horizontal.decrease.circle", description: Text("Change them from the filter button."))
        } else {
            ContentUnavailableView("Nothing in \(shelf.name)", systemImage: "folder", description: Text("Long-press a title and choose Edit categories."))
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ snap: Snapshot) -> some ToolbarContent {
        if selecting {
            ToolbarItem(placement: .topBarLeading) { Button("Done") { endSelection() } }
            ToolbarItem(placement: .topBarTrailing) {
                let all = Set((snap.items[snap.currentId] ?? []).map(\.key))
                let everything = !all.isEmpty && selection.isSuperset(of: all)
                Menu("Select") {
                    Button(everything ? "Deselect all" : "Select all", systemImage: "checkmark.circle") {
                        if everything { selection.subtract(all) } else { selection.formUnion(all) }
                    }
                    // Flips every title on this shelf; selections on other shelves stay.
                    Button("Select inverse", systemImage: "circle.lefthalf.filled") {
                        selection = selection.subtracting(all).union(all.subtracting(selection))
                    }
                }
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSheet = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .overlay(alignment: .topTrailing) {
                            // The dot says a filter is hiding titles.
                            if filters.isActive {
                                Circle().fill(Color.accentColor).frame(width: 8, height: 8).offset(x: 5, y: -4)
                            }
                        }
                }
                .accessibilityLabel(filters.isActive ? "Filter, sort and display, filters active" : "Filter, sort and display")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Select", systemImage: "checkmark.circle") { withAnimation { selecting = true } }
                    Button("Open random entry", systemImage: "dice") { openRandom(snap) }
                        .disabled((snap.items[snap.currentId] ?? []).isEmpty)
                    Button("Update this category", systemImage: "arrow.triangle.2.circlepath") {
                        let titles = snap.buckets[snap.currentId] ?? []
                        Task { await updater.update(titles, repo: repo, sources: sources) }
                    }
                    .disabled(updater.isRunning || (snap.buckets[snap.currentId] ?? []).isEmpty)
                    Button("Update library", systemImage: "arrow.clockwise") {
                        Task { await updater.update(repo.library, repo: repo, sources: sources) }
                    }
                    .disabled(updater.isRunning)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var selectionBar: some View {
        HStack {
            barButton("Categories", icon: "folder") { settingCategories = true }
            barMenu("Mark", icon: "checkmark.circle") {
                Button("Mark as read", systemImage: "checkmark.circle") { mark(read: true) }
                Button("Mark as unread", systemImage: "circle") { mark(read: false) }
            }
            barMenu("Download", icon: "arrow.down.circle") {
                Button("Download unread", systemImage: "arrow.down.circle") { download(unreadOnly: true) }
                Button("Download all", systemImage: "arrow.down.circle.fill") { download(unreadOnly: false) }
                Button("Delete downloads", systemImage: "trash", role: .destructive) { confirmDeleteDownloads = true }
            }
            barButton("Remove", icon: "trash", role: .destructive) { confirmRemove = true }
        }
        .disabled(selection.isEmpty)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func barButton(_ title: String, icon: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) { barLabel(title, icon: icon) }
    }

    private func barMenu<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        Menu(content: content) { barLabel(title, icon: icon) }
    }

    private func barLabel(_ title: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 18, weight: .medium))
            Text(title).font(.caption2.weight(.medium))
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private func startSelecting(_ ref: MangaRef) {
        selection = [LibraryManga.makeKey(sourceId: ref.sourceId, url: ref.url)]
        withAnimation { selecting = true }
    }

    private func mark(read: Bool) {
        repo.setRead(selectedManga.flatMap(\.chapters), read)
        endSelection()
    }

    /// Queues oldest chapters first, the order they should be read in.
    private func download(unreadOnly: Bool) {
        let chapters = selectedManga.flatMap { $0.sortedChapters.reversed().filter { !unreadOnly || !$0.read } }
        downloads.enqueue(chapters)
        endSelection()
    }

    private func openRandom(_ snap: Snapshot) {
        guard let pick = (snap.items[snap.currentId] ?? []).randomElement() else { return }
        path.append(.manga(pick.ref))
    }

    private func endSelection() {
        selection = []
        withAnimation { selecting = false }
    }
}
