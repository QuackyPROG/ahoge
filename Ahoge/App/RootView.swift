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
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var repoError: String?
    @State private var showOnboarding = false

    var body: some View {
        let palette = theme.palette(pureBlack: pureBlack)
        let unseen = repo.updates(since: max(Date(timeIntervalSince1970: lastSeen), UpdatesPrefs.cutoff)).count
        let badge = updatesBadge ? unseen : 0
        tabs(badge: badge)
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
        .onAppear {
            // Someone updating from an older version already has a library: no welcome guide.
            guard !Pref.onboarded.value() else { return }
            if !repo.library.isEmpty || !extensions.repos.isEmpty { Pref.onboarded.set(true) } else { showOnboarding = true }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                Pref.onboarded.set(true)
                showOnboarding = false
            }
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

    /// Tabs on a phone; on a wide screen (iPad) a sidebar with the screen beside it.
    @ViewBuilder private func tabs(badge: Int) -> some View {
        if sizeClass == .regular {
            NavigationSplitView {
                List(selection: sidebarSelection) {
                    ForEach(AppTab.allCases, id: \.self) { tab in
                        Label(tab.title, systemImage: tab.symbol)
                            .badge(tab == .updates ? badge : tab == .more ? downloads.queue.count : 0)
                            .tag(tab)
                    }
                }
                .navigationTitle(AppInfo.name)
            } detail: {
                screen(navigator.tab)
            }
        } else {
            TabView(selection: $navigator.tab) {
                screen(.library)
                    .tabItem { Label(AppTab.library.title, systemImage: AppTab.library.symbol) }
                    .tag(AppTab.library)
                screen(.updates)
                    .tabItem { Label(AppTab.updates.title, systemImage: AppTab.updates.symbol) }
                    .badge(badge)
                    .tag(AppTab.updates)
                screen(.history)
                    .tabItem { Label(AppTab.history.title, systemImage: AppTab.history.symbol) }
                    .tag(AppTab.history)
                screen(.browse)
                    .tabItem { Label(AppTab.browse.title, systemImage: AppTab.browse.symbol) }
                    .tag(AppTab.browse)
                screen(.more)
                    .tabItem { Label(AppTab.more.title, systemImage: AppTab.more.symbol) }
                    .badge(downloads.queue.count)
                    .tag(AppTab.more)
            }
        }
    }

    @ViewBuilder private func screen(_ tab: AppTab) -> some View {
        switch tab {
        case .library: LibraryView()
        case .updates: UpdatesView()
        case .history: HistoryView()
        case .browse: BrowseView()
        case .more: MoreView()
        }
    }

    /// The sidebar list selects an optional; a tab is always selected.
    private var sidebarSelection: Binding<AppTab?> {
        Binding(get: { navigator.tab }, set: { if let tab = $0 { navigator.tab = tab } })
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
