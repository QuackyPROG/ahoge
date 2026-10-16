// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

extension Notification.Name {
    static let ahogeLibraryReselected = Notification.Name("ahoge.library.reselected")
    static let ahogeBrowseReselected = Notification.Name("ahoge.browse.reselected")
}
private enum AppTab: Int, CaseIterable, Identifiable {
    case library, updates, history, browse, more
    var id: Int { rawValue }
    var title: String { ["Library", "Updates", "History", "Browse", "More"][rawValue] }
    var symbol: String { ["books.vertical", "arrow.triangle.2.circlepath", "clock", "safari", "ellipsis"][rawValue] }
}
struct RootTabView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: AppTab = .library
    @State private var paths = Array(repeating: NavigationPath(), count: 5)
    @State private var presentation: AppTab?
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                stack(.library)
            }
            Tab("Updates", systemImage: "arrow.triangle.2.circlepath", value: AppTab.updates) {
                stack(.updates)
            }.badge(model.unreadUpdatesCount)
            Tab("History", systemImage: "clock", value: AppTab.history) {
                stack(.history)
            }
            Tab("Browse", systemImage: "safari", value: AppTab.browse) {
                stack(.browse)
            }.badge(model.sourcePackageUpdateCount)
            Tab("More", systemImage: "ellipsis", value: AppTab.more) {
                stack(.more)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(model.chromeTint)
        .toolbarBackground(AhogePalette.canvas, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sheet(item: $presentation) { tab in
            NavigationStack {
                Group {
                    if tab == .updates { DownloadQueueView() }
                    else if tab == .more { SettingsHomeView() }
                    else if tab == .history, let item = model.historyEntries(searchText: "").first(where: { model.canReadChapter($0.2, manga: $0.1) }) {
                        ReaderView(manga: item.1, initialChapter: item.2)
                    }
                }.toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { presentation = nil } } }
            }
        }
    }
    private func stack(_ tab: AppTab) -> some View {
        NavigationStack(path: $paths[tab.rawValue]) {
            Group {
                switch tab {
                case .library: LibraryView()
                case .updates: UpdatesView()
                case .history: HistoryView()
                case .browse: BrowseView()
                case .more: MoreView()
                }
            }.background {
                // Install for both the compact tab bar and the native iPad sidebar.
                TabBarControllerAccessor { index in
                    if let tab = AppTab(rawValue: index) { reselect(tab) }
                }.frame(width: 0, height: 0)
            }
        }
    }
    private func reselect(_ tab: AppTab) {
        guard presentation == nil else { return }
        paths[tab.rawValue] = NavigationPath()
        switch tab {
        case .library: NotificationCenter.default.post(name: .ahogeLibraryReselected, object: nil)
        case .browse: NotificationCenter.default.post(name: .ahogeBrowseReselected, object: nil)
        case .updates, .more: presentation = tab
        case .history: if let item = model.historyEntries(searchText: "").first(where: { model.canReadChapter($0.2, manga: $0.1) }), model.canReadChapter(item.2, manga: item.1) { presentation = tab }
        }
    }
}
