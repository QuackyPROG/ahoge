import SwiftUI

struct BrowseView: View {
    enum Tab: String, CaseIterable {
        case sources = "Sources"
        case extensions = "Extensions"
    }

    @State private var tab: Tab = .sources
    @EnvironmentObject private var navigator: AppNavigator
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack(path: navigator.binding(for: .browse)) {
            Group {
                switch tab {
                case .sources: SourcesView()
                case .extensions: ExtensionsView()
                }
            }
            // At accessibility text sizes the picker cannot share the bar with the trailing buttons,
            // so it gets its own row under the bar, like the Library sheet's tabs.
            .safeAreaInset(edge: .top, spacing: 0) {
                if typeSize.isAccessibilitySize {
                    picker
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                }
            }
            .navigationTitle("Browse")
            .themedScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !typeSize.isAccessibilitySize {
                    ToolbarItem(placement: .principal) { picker }
                }
            }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }

    /// Sized by its labels, so it fits beside "Update all" and the repositories button on a 375 pt phone.
    private var picker: some View {
        Picker("Browse", selection: $tab) {
            ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}
