import SwiftUI

struct RootView: View {
    @AppStorage(ThemePrefs.theme) private var theme = AppTheme.standard
    @AppStorage(ThemePrefs.mode) private var mode = ThemeMode.system
    @AppStorage(ThemePrefs.pureBlack) private var pureBlack = false
    @EnvironmentObject private var updater: LibraryUpdater
    @EnvironmentObject private var repo: LibraryRepository
    @AppStorage(UpdatesPrefs.lastSeen) private var lastSeen = 0.0

    var body: some View {
        let palette = theme.palette(pureBlack: pureBlack)
        let unseen = repo.updates(since: max(Date(timeIntervalSince1970: lastSeen), UpdatesPrefs.cutoff)).count
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
            UpdatesView()
                .tabItem { Label("Updates", systemImage: "bell") }
                .badge(unseen)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            BrowseView()
                .tabItem { Label("Browse", systemImage: "safari") }
            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .tint(palette.primary.color)
        .environment(\.palette, palette)
        .preferredColorScheme(mode.colorScheme)
        .onAppear(perform: applyWindowStyle)
        .onChange(of: mode, initial: true) { applyWindowStyle() }
        .onChange(of: theme) { applyWindowStyle() }
        .onChange(of: pureBlack) { applyWindowStyle() }
        .onReceive(NotificationCenter.default.publisher(for: .readerDidClose)) { _ in
            DispatchQueue.main.async { applyWindowStyle() }
        }
        .alert("Some titles could not be updated", isPresented: Binding(get: { !updater.failures.isEmpty }, set: { if !$0 { updater.failures = [] } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(updater.failures.joined(separator: "\n"))
        }
    }

    /// Pushes mode and tint onto the UIKit windows too: preferredColorScheme(nil) can stick and covers force .dark.
    private func applyWindowStyle() {
        let p = theme.palette(pureBlack: pureBlack)
        let tint = UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: p.primary.dark) : UIColor(rgb: p.primary.light) }
        let style: UIUserInterfaceStyle = switch mode { case .system: .unspecified; case .light: .light; case .dark: .dark }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = style
                window.tintColor = tint
            }
        }
    }
}
