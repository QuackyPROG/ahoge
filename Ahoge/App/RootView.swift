import SwiftUI

struct RootView: View {
    @AppStorage(Pref.theme.name) private var theme = AppTheme.standard
    @AppStorage(Pref.themeMode.name) private var mode = ThemeMode.system
    @AppStorage(Pref.pureBlack.name) private var pureBlack = false
    @EnvironmentObject private var updater: LibraryUpdater
    @EnvironmentObject private var repo: LibraryRepository
    @EnvironmentObject private var extensions: ExtensionStore
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var navigator: AppNavigator
    @AppStorage(Pref.updatesBadge.name) private var updatesBadge = Pref.updatesBadge.defaultValue
    @AppStorage(Pref.updatesLastSeen.name) private var lastSeen = 0.0
    @AppStorage(Pref.secureScreen.name) private var secureScreen = false
    @AppStorage(Pref.downloadedOnly.name) private var downloadedOnly = false
    @AppStorage(Pref.incognito.name) private var incognito = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var repoError: String?
    @ObservedObject private var updateCenter = UpdateCenter.shared

    var body: some View {
        let palette = theme.palette(pureBlack: pureBlack)
        let unseen = repo.updates(since: max(Date(timeIntervalSince1970: lastSeen), UpdatesPrefs.cutoff)).count
        let badge = updatesBadge ? unseen : 0
        TabView(selection: $navigator.tab) {
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(AppTab.library)
            UpdatesView()
                .tabItem { Label("Updates", systemImage: "bell") }
                .badge(badge)
                .tag(AppTab.updates)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(AppTab.history)
            BrowseView()
                .tabItem { Label("Browse", systemImage: "safari") }
                .tag(AppTab.browse)
            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .badge(downloads.queue.count)
                .tag(AppTab.more)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // Mihon's banners while Downloaded only or Incognito mode is on.
            VStack(spacing: 0) {
                if downloadedOnly {
                    Text("Downloaded only")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.onPrimary.color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .background(palette.primary.color)
                }
                if incognito {
                    Text("Incognito mode")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .background(Color.gray)
                }
            }
        }
        .tint(palette.primary.color)
        .environment(\.palette, palette)
        .preferredColorScheme(mode.colorScheme)
        .onAppear(perform: applyWindowStyle)
        .onAppear { BackgroundRefresh.schedule() }
        .onAppear { AppLock.shared.start() }
        .task { await updateCenter.checkIfDue() }
        .sheet(item: $updateCenter.available) { UpdateSheet(release: $0) }
        .alert("Check for updates", isPresented: Binding(get: { updateCenter.manualResult != nil }, set: { if !$0 { updateCenter.manualResult = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(updateCenter.manualResult ?? "")
        }
        .onChange(of: badge, initial: true) { UpdateNotifier.setBadge(badge) }
        .onChange(of: mode, initial: true) { applyWindowStyle() }
        .onChange(of: theme) { applyWindowStyle() }
        .onChange(of: pureBlack) { applyWindowStyle() }
        .onChange(of: scenePhase) { _, phase in
            PrivacyShield.setVisible((secureScreen || Pref.requireUnlock.value()) && phase != .active)
            AppLock.shared.phaseChanged(to: phase)
            if phase == .background {
                AutoBackup.runIfDue(repo: repo, store: extensions)
                BackgroundRefresh.schedule()
            }
            downloads.setBackground(phase == .background)
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerDidClose)) { _ in
            DispatchQueue.main.async { applyWindowStyle() }
        }
        .onOpenURL { navigator.open($0, sources: extensions.installed) }
        .alert("Add repository?", isPresented: Binding(get: { navigator.pendingRepo != nil }, set: { if !$0 { navigator.pendingRepo = nil } })) {
            Button("Add") {
                guard let url = navigator.pendingRepo else { return }
                navigator.pendingRepo = nil
                Task {
                    do { try await extensions.addRepo(url.absoluteString) } catch { repoError = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) { navigator.pendingRepo = nil }
        } message: {
            Text("A link asks to add \(navigator.pendingRepo?.absoluteString ?? "a repository"). Only add repositories you trust.")
        }
        .alert("Could not add the repository", isPresented: Binding(get: { repoError != nil }, set: { if !$0 { repoError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(repoError ?? "")
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
