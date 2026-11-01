import SwiftData
import SwiftUI

struct LibraryView: View {
    enum Sort: String, CaseIterable, Identifiable {
        case title = "Title"
        case dateAdded = "Date added"
        case lastRead = "Last read"
        case unread = "Unread count"
        var id: String { rawValue }
    }

    @Query(filter: #Predicate<LibraryManga> { $0.inLibrary == true }) private var library: [LibraryManga]
    @EnvironmentObject private var sources: SourceManager
    @Environment(\.modelContext) private var context
    @AppStorage("library.sort") private var sort: Sort = .title
    @State private var search = ""
    @State private var updating = false
    @State private var failures: [String] = []

    private var visible: [LibraryManga] {
        let filtered = search.isEmpty ? library : library.filter { $0.title.localizedCaseInsensitiveContains(search) }
        switch sort {
        case .title: return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .dateAdded: return filtered.sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
        case .lastRead: return filtered.sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
        case .unread: return filtered.sorted { $0.unreadCount > $1.unreadCount }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if library.isEmpty {
                    ContentUnavailableView("Your library is empty", systemImage: "books.vertical", description: Text("Add manga from Browse."))
                        .padding(.top, 80)
                }
                let unread = Dictionary(visible.map { ($0.key, $0.unreadCount) }, uniquingKeysWith: { first, _ in first })
                MangaGrid(items: visible.map(\.ref), badge: { ref in
                    let count = unread[LibraryManga.makeKey(sourceId: ref.sourceId, url: ref.url)] ?? 0
                    return count > 0 ? "\(count)" : nil
                })
            }
            .navigationTitle("Library")
            .searchable(text: $search)
            .refreshable { await updateAll() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if updating {
                    Label("Updating library…", systemImage: "arrow.clockwise")
                        .padding(10)
                        .background(.thinMaterial, in: Capsule())
                        .padding()
                }
            }
            .alert("Some titles could not be updated", isPresented: Binding(get: { !failures.isEmpty }, set: { if !$0 { failures = [] } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failures.joined(separator: "\n"))
            }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }

    /// Re-fetches chapter lists for every library title, one after another.
    private func updateAll() async {
        updating = true
        defer { updating = false }
        let repo = LibraryRepository(context: context)
        var errors: [String] = []
        for manga in library {
            do {
                let source = try sources.source(manga.sourceId)
                repo.applyChapters(try await source.chapters(url: manga.url), to: manga)
            } catch {
                errors.append("\(manga.title): \(error.localizedDescription)")
            }
        }
        failures = errors
    }
}
