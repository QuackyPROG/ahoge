import SwiftUI

struct LibraryView: View {
    enum Sort: String, CaseIterable, Identifiable {
        case title = "Title"
        case dateAdded = "Date added"
        case lastRead = "Last read"
        case unread = "Unread count"
        var id: String { rawValue }
    }

    @EnvironmentObject private var sources: SourceManager
    @EnvironmentObject private var repo: LibraryRepository
    @EnvironmentObject private var updater: LibraryUpdater
    @AppStorage(Pref.librarySort.name) private var sort: Sort = .title
    @AppStorage(Pref.libraryShelf.name) private var shelf = 0
    @AppStorage(Pref.libraryContinueButton.name) private var continueButton = false
    @State private var reading: (manga: LibraryManga, chapter: ChapterRecord)?
    @State private var search = ""
    @State private var selecting = false
    @State private var selection = Set<String>()
    @State private var settingCategories = false
    @State private var confirmRemove = false

    /// One pass over the library: titles per shelf (0 = in no category), the shelf list and the current shelf.
    private struct Snapshot {
        let buckets: [Int: [LibraryManga]]
        let shelves: [LibraryShelf]
        let currentId: Int
    }

    private func snapshot() -> Snapshot {
        var buckets: [Int: [LibraryManga]] = [:]
        for title in repo.library {
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
        return Snapshot(buckets: buckets, shelves: shelves, currentId: currentId)
    }

    private func visible(_ all: [LibraryManga]) -> [LibraryManga] {
        let filtered = search.isEmpty ? all : all.filter { $0.title.localizedCaseInsensitiveContains(search) }
        switch sort {
        case .title: return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .dateAdded: return filtered.sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
        case .lastRead: return filtered.sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
        case .unread: return filtered.sorted { $0.unreadCount > $1.unreadCount }
        }
    }

    private var selectedManga: [LibraryManga] { repo.library.filter { selection.contains($0.key) } }

    var body: some View {
        let snap = snapshot()
        let shelves = snap.shelves
        let currentId = snap.currentId
        let current = Binding(get: { currentId }, set: { shelf = $0 })
        NavigationStack {
            VStack(spacing: 0) {
                if shelves.count > 1 {
                    CategoryTabBar(
                        shelves: shelves,
                        counts: Dictionary(uniqueKeysWithValues: shelves.map { ($0.id, (snap.buckets[$0.id] ?? []).count) }),
                        selection: current
                    )
                }
                TabView(selection: current) {
                    ForEach(shelves) { item in
                        page(item, titles: snap.buckets[item.id] ?? []).tag(item.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .id(shelves.map { $0.id })
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
            .confirmationDialog(selection.count == 1 ? "Remove 1 title from your library?" : "Remove \(selection.count) titles from your library?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    for manga in selectedManga { repo.setInLibrary(manga, false) }
                    endSelection()
                }
            }
            .fullScreenCover(isPresented: Binding(get: { reading != nil }, set: { if !$0 { reading = nil } })) {
                if let reading { ReaderView(sourceId: reading.manga.sourceId, manga: reading.manga, chapter: reading.chapter) }
            }
            .themedScreen()
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }

    private func page(_ shelf: LibraryShelf, titles: [LibraryManga]) -> some View {
        let items = visible(titles)
        let unread = Dictionary(items.map { ($0.key, $0.unreadCount) }, uniquingKeysWith: { first, _ in first })
        let onContinue: ((MangaRef) -> Void)? = continueButton ? { ref in
            if let manga = repo.manga(sourceId: ref.sourceId, url: ref.url), let chapter = manga.nextUnreadChapter {
                reading = (manga, chapter)
            }
        } : nil
        return ScrollView {
            if items.isEmpty { emptyState(shelf).padding(.top, 80) }
            MangaGrid(
                items: items.map(\.ref),
                badge: { ref in
                    let count = unread[LibraryManga.makeKey(sourceId: ref.sourceId, url: ref.url)] ?? 0
                    return count > 0 ? "\(count)" : nil
                },
                selection: selecting ? $selection : nil,
                librarySelect: { startSelecting($0) },
                onContinue: onContinue,
                canContinue: { (unread[LibraryManga.makeKey(sourceId: $0.sourceId, url: $0.url)] ?? 0) > 0 }
            )
            .padding(.vertical, 8)
        }
        // Mihon refreshes the category on screen.
        .refreshable { await updater.update(titles, repo: repo, sources: sources) }
    }

    @ViewBuilder
    private func emptyState(_ shelf: LibraryShelf) -> some View {
        if repo.library.isEmpty {
            ContentUnavailableView("Your library is empty", systemImage: "books.vertical", description: Text("Add manga from Browse."))
        } else if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            ContentUnavailableView("Nothing in \(shelf.name)", systemImage: "folder", description: Text("Long-press a title and choose Edit categories."))
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ snap: Snapshot) -> some ToolbarContent {
        if selecting {
            ToolbarItem(placement: .topBarLeading) { Button("Done") { endSelection() } }
            ToolbarItem(placement: .topBarTrailing) {
                let all = Set(visible(snap.buckets[snap.currentId] ?? []).map(\.key))
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
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Continue reading button", systemImage: "play.circle", isOn: $continueButton)
                    Button("Select", systemImage: "checkmark.circle") { withAnimation { selecting = true } }
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
            barButton("Read", icon: "checkmark.circle") { mark(read: true) }
            barButton("Unread", icon: "circle") { mark(read: false) }
            barButton("Remove", icon: "trash", role: .destructive) { confirmRemove = true }
        }
        .disabled(selection.isEmpty)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func barButton(_ title: String, icon: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18, weight: .medium))
                Text(title).font(.caption2.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private func startSelecting(_ ref: MangaRef) {
        selection = [LibraryManga.makeKey(sourceId: ref.sourceId, url: ref.url)]
        withAnimation { selecting = true }
    }

    private func mark(read: Bool) {
        repo.setRead(selectedManga.flatMap(\.chapters), read)
        endSelection()
    }

    private func endSelection() {
        selection = []
        withAnimation { selecting = false }
    }
}
