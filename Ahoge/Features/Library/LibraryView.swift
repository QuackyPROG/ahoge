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
    @State private var search = ""

    private var library: [LibraryManga] { repo.library }

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
            .themedScreen()
            .searchable(text: $search)
            .refreshable { await updater.update(library, repo: repo, sources: sources) }
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
                if updater.isRunning {
                    Label("Updating library… \(updater.done)/\(updater.total)", systemImage: "arrow.clockwise")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding()
                }
            }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }
}
