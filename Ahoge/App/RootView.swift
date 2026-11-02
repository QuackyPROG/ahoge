import SwiftUI

struct RootView: View {
    @AppStorage(ThemePrefs.theme) private var theme = AppTheme.standard
    @AppStorage(ThemePrefs.mode) private var mode = ThemeMode.system
    @AppStorage(ThemePrefs.pureBlack) private var pureBlack = false
    @EnvironmentObject private var updater: LibraryUpdater

    var body: some View {
        let palette = theme.palette(pureBlack: pureBlack)
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
            BrowseView()
                .tabItem { Label("Browse", systemImage: "safari") }
            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .tint(palette.primary.color)
        .environment(\.palette, palette)
        .preferredColorScheme(mode.colorScheme)
        .alert("Some titles could not be updated", isPresented: Binding(get: { !updater.failures.isEmpty }, set: { if !$0 { updater.failures = [] } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(updater.failures.joined(separator: "\n"))
        }
    }
}
