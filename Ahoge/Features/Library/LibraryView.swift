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
    @AppStorage("library.sort") private var sort: Sort = .title
    @AppStorage(LibraryPrefs.shelf) private var shelf = 0
    @State private var search = ""
    @State private var selecting = false
    @State private var selection = Set<String>()
    @State private var settingCategories = false
    @State private var confirmRemove = false

    /// Default (titles in no category) when it has any or there are no categories, then each category.
    private var shelves: [LibraryShelf] {
        let named = repo.categories.map { LibraryShelf(id: Int($0.id), name: $0.name) }
        if named.isEmpty || !repo.library(in: nil).isEmpty {
            return [LibraryShelf(id: 0, name: "Default")] + named
        }
        return named
    }

    private var currentShelf: Int {
        let shelves = shelves
        return shelves.contains { $0.id == shelf } ? shelf : shelves.first?.id ?? 0
    }

    private func titles(on shelf: Int) -> [LibraryManga] {
        repo.library(in: shelf == 0 ? nil : Int64(shelf))
    }

    private func visible(on shelf: Int) -> [LibraryManga] {
        let all = titles(on: shelf)
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
        let shelves = shelves
        let current = Binding(get: { currentShelf }, set: { shelf = $0 })
        NavigationStack {
            VStack(spacing: 0) {
                if shelves.count > 1 {
                    CategoryTabBar(
                        shelves: shelves,
                        counts: Dictionary(uniqueKeysWithValues: shelves.map { ($0.id, titles(on: $0.id).count) }),
                        selection: current
                    )
                }
                TabView(selection: current) {
                    ForEach(shelves) { item in
                        page(item).tag(item.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle(selecting ? "\(selection.count) selected" : "Library")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search)
            .toolbar { toolbar }
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
            .sheet(isPresented: $settingCategories, onDismiss: endSelection) { SetCategoriesSheet(manga: selectedManga) }
            .confirmationDialog("Remove \(selection.count) from your library?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    for manga in selectedManga { repo.setInLibrary(manga, false) }
                    endSelection()
                }
            }
            .themedScreen()
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }

    private func page(_ shelf: LibraryShelf) -> some View {
        let items = visible(on: shelf.id)
        let unread = Dictionary(items.map { ($0.key, $0.unreadCount) }, uniquingKeysWith: { first, _ in first })
        return ScrollView {
            if items.isEmpty { emptyState(shelf).padding(.top, 80) }
            MangaGrid(
                items: items.map(\.ref),
                badge: { ref in
                    let count = unread[LibraryManga.makeKey(sourceId: ref.sourceId, url: ref.url)] ?? 0
                    return count > 0 ? "\(count)" : nil
                },
                selection: selecting ? $selection : nil,
                librarySelect: { startSelecting($0) }
            )
            .padding(.vertical, 8)
        }
        // Mihon refreshes the category on screen.
        .refreshable { await updater.update(titles(on: shelf.id), repo: repo, sources: sources) }
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
    private var toolbar: some ToolbarContent {
        if selecting {
            ToolbarItem(placement: .topBarLeading) { Button("Done") { endSelection() } }
            ToolbarItem(placement: .topBarTrailing) {
                let all = Set(visible(on: currentShelf).map(\.key))
                let everything = !all.isEmpty && selection.isSuperset(of: all)
                Button(everything ? "Deselect all" : "Select all") { selection = everything ? [] : all }
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
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
