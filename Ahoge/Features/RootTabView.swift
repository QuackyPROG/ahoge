// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

private enum AppTab: Hashable {
    case library
    case explore
    case activity
    case more
}

struct RootTabView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: AppTab = .library
    @State private var previousTab: AppTab = .library
    @State private var libraryPath = NavigationPath()
    @State private var explorePath = NavigationPath()
    @State private var activityPath = NavigationPath()
    @State private var morePath = NavigationPath()

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $libraryPath) {
                LibraryView()
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }
            .tag(AppTab.library)

            NavigationStack(path: $explorePath) {
                BrowseView()
            }
            .tabItem { Label("Explore", systemImage: "safari") }
            .tag(AppTab.explore)

            NavigationStack(path: $activityPath) {
                ActivityView()
            }
            .tabItem { Label("Activity", systemImage: "clock.badge") }
            .badge(model.unreadUpdatesCount > 0 ? model.unreadUpdatesCount : 0)
            .tag(AppTab.activity)

            NavigationStack(path: $morePath) {
                MoreView()
            }
            .tabItem { Label("More", systemImage: "ellipsis.circle") }
            .tag(AppTab.more)
        }
        .tint(model.chromeTint)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .onChange(of: selectedTab) { old, new in
            if new == old { popToRoot(for: new) }
            previousTab = new
        }
    }

    private func popToRoot(for tab: AppTab) {
        switch tab {
        case .library: libraryPath = NavigationPath()
        case .explore: explorePath = NavigationPath()
        case .activity: activityPath = NavigationPath()
        case .more: morePath = NavigationPath()
        }
    }
}
