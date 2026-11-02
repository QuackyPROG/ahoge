import SwiftUI

struct BrowseView: View {
    enum Tab: String, CaseIterable {
        case sources = "Sources"
        case extensions = "Extensions"
    }

    @State private var tab: Tab = .sources

    var body: some View {
        NavigationStack {
            Group {
                switch tab {
                case .sources: SourcesView()
                case .extensions: ExtensionsView()
                }
            }
            .navigationTitle("Browse")
            .themedScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Browse", selection: $tab) {
                        ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
            }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }
}
