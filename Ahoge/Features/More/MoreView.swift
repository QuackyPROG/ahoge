import SwiftUI

struct MoreView: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var repo: LibraryRepository
    @EnvironmentObject private var downloads: DownloadManager
    @AppStorage(Pref.downloadedOnly.name) private var downloadedOnly = false
    @AppStorage(Pref.libraryDefaultCategory.name) private var defaultCategory = LibraryPrefs.alwaysAsk
    @AppStorage(Pref.browseHideInLibrary.name) private var hideInLibrary = false
    @AppStorage(Pref.secureScreen.name) private var secureScreen = false
    @AppStorage(Pref.incognito.name) private var incognito = false
    @AppStorage(Pref.requireUnlock.name) private var requireUnlock = false
    @AppStorage(Pref.lockAfter.name) private var lockAfter = 0
    @AppStorage(Pref.swipeRight.name) private var swipeRight = Pref.swipeRight.defaultValue
    @AppStorage(Pref.swipeLeft.name) private var swipeLeft = Pref.swipeLeft.defaultValue
    @AppStorage(Pref.hideMissingChapters.name) private var hideMissing = false
    @AppStorage(Pref.markDuplicateRead.name) private var markDuplicateRead = false
    @State private var showRepos = false
    @State private var showGuide = false
    @ObservedObject private var updates = UpdateCenter.shared
    @AppStorage(Pref.checkUpdates.name) private var checkUpdates = Pref.checkUpdates.defaultValue

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 6) {
                        Image(systemName: "book.pages.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(palette.onPrimary.color)
                            .frame(width: 72, height: 72)
                            .background(palette.primary.color.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Text(AppInfo.name).font(.title2.bold())
                        Text("Version \(AppInfo.version)").font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                Section {
                    Toggle(isOn: $downloadedOnly) {
                        Label { Text("Downloaded only") } icon: { SettingsIcon(systemName: "icloud.slash.fill", color: .blue) }
                    }
                } footer: {
                    Text("Library, Updates and History show only downloaded chapters.")
                }
                .themedRows()

                Section {
                    NavigationLink { AppearanceView() } label: {
                        Label { Text("Appearance") } icon: { SettingsIcon(systemName: "paintpalette.fill", color: .purple) }
                    }
                    Button { showRepos = true } label: {
                        Label { Text("Extension repositories").foregroundStyle(.primary) } icon: { SettingsIcon(systemName: "shippingbox.fill", color: .orange) }
                    }
                }
                .themedRows()

                Section("Library") {
                    NavigationLink { CategoriesView() } label: {
                        Label { Text("Categories") } icon: { SettingsIcon(systemName: "folder.fill", color: .blue) }
                    }
                    NavigationLink { UpdateSettingsView() } label: {
                        Label { Text("Library updates") } icon: { SettingsIcon(systemName: "arrow.triangle.2.circlepath", color: .orange) }
                    }
                    NavigationLink { MigrateSourcesView() } label: {
                        Label { Text("Migrate") } icon: { SettingsIcon(systemName: "arrow.left.arrow.right", color: .green) }
                    }
                    Picker(selection: $defaultCategory) {
                        Text("Always ask").tag(LibraryPrefs.alwaysAsk)
                        Text("Default").tag(LibraryPrefs.uncategorized)
                        ForEach(repo.categories) { Text($0.name).tag(Int($0.id)) }
                    } label: {
                        Label { Text("Default category") } icon: { SettingsIcon(systemName: "tray.and.arrow.down.fill", color: .teal) }
                    }
                }
                .themedRows()

                Section("Chapters") {
                    Picker(selection: $swipeRight) {
                        ForEach(ChapterSwipeAction.allCases) { Text($0.title).tag($0.rawValue) }
                    } label: {
                        Label { Text("Swipe right") } icon: { SettingsIcon(systemName: "arrow.right.circle.fill", color: .blue) }
                    }
                    Picker(selection: $swipeLeft) {
                        ForEach(ChapterSwipeAction.allCases) { Text($0.title).tag($0.rawValue) }
                    } label: {
                        Label { Text("Swipe left") } icon: { SettingsIcon(systemName: "arrow.left.circle.fill", color: .orange) }
                    }
                    Toggle(isOn: $hideMissing) {
                        Label { Text("Hide missing chapter count") } icon: { SettingsIcon(systemName: "exclamationmark.triangle.fill", color: .yellow) }
                    }
                    Toggle(isOn: $markDuplicateRead) {
                        Label { Text("Mark duplicate chapters read") } icon: { SettingsIcon(systemName: "checkmark.circle.fill", color: .green) }
                    }
                } footer: {
                    Text("A new chapter with the number of one you already read is marked read when a title refreshes.")
                }
                .themedRows()

                Section("Downloads") {
                    NavigationLink { DownloadQueueView() } label: {
                        Label { Text("Download queue") } icon: { SettingsIcon(systemName: "arrow.down.circle.fill", color: .blue) }
                            .badge(downloads.queue.count)
                    }
                    NavigationLink { DownloadSettingsView() } label: {
                        Label { Text("Download settings") } icon: { SettingsIcon(systemName: "gearshape.fill", color: .gray) }
                    }
                }
                .themedRows()

                Section("Browse") {
                    Toggle(isOn: $hideInLibrary) {
                        Label { Text("Hide titles in your library") } icon: { SettingsIcon(systemName: "eye.slash.fill", color: .indigo) }
                    }
                }
                .themedRows()

                Section("Privacy") {
                    Toggle(isOn: $incognito) {
                        Label { Text("Incognito mode") } icon: { SettingsIcon(systemName: "eyeglasses", color: .gray) }
                    }
                    Toggle(isOn: $secureScreen) {
                        Label { Text("Hide content in app switcher") } icon: { SettingsIcon(systemName: "lock.shield.fill", color: .green) }
                    }
                    Toggle(isOn: $requireUnlock) {
                        Label { Text("Require unlock") } icon: { SettingsIcon(systemName: "faceid", color: .blue) }
                    }
                    if requireUnlock {
                        Picker(selection: $lockAfter) {
                            ForEach(LockPolicy.afterOptions, id: \.self) { Text(LockPolicy.label($0)).tag($0) }
                        } label: {
                            Label { Text("Lock") } icon: { SettingsIcon(systemName: "timer", color: .orange) }
                        }
                    }
                }
                .themedRows()

                Section("Data") {
                    NavigationLink { StatisticsView() } label: {
                        Label { Text("Statistics") } icon: { SettingsIcon(systemName: "chart.bar.fill", color: .pink) }
                    }
                    NavigationLink { DataStorageView() } label: {
                        Label { Text("Data and storage") } icon: { SettingsIcon(systemName: "externaldrive.fill", color: .gray) }
                    }
                    NavigationLink { AdvancedView() } label: {
                        Label { Text("Advanced") } icon: { SettingsIcon(systemName: "wrench.and.screwdriver.fill", color: .gray) }
                    }
                }
                .themedRows()

                Section("Help") {
                    Button { showGuide = true } label: {
                        Label { Text("Welcome guide").foregroundStyle(.primary) } icon: { SettingsIcon(systemName: "hand.wave.fill", color: .yellow) }
                    }
                }
                .themedRows()

                Section("About") {
                    Link(destination: URL(string: "https://github.com/QuackyPROG/ahoge")!) {
                        Label { Text("Source code").foregroundStyle(.primary) } icon: { SettingsIcon(systemName: "chevron.left.forwardslash.chevron.right", color: .gray) }
                    }
                    NavigationLink { LicensesView() } label: {
                        Label { Text("Licenses") } icon: { SettingsIcon(systemName: "doc.text.fill", color: .gray) }
                    }
                    NavigationLink { WhatsNewView() } label: {
                        Label { Text("What's new") } icon: { SettingsIcon(systemName: "sparkles", color: .yellow) }
                    }
                    Button { Task { await updates.checkNow() } } label: {
                        Label { Text(updates.checking ? "Checking…" : "Check for updates").foregroundStyle(.primary) } icon: { SettingsIcon(systemName: "arrow.down.app.fill", color: .blue) }
                    }
                    .disabled(updates.checking)
                    Toggle(isOn: $checkUpdates) {
                        Label { Text("Check for updates on launch") } icon: { SettingsIcon(systemName: "bell.badge.fill", color: .red) }
                    }
                }
                .themedRows()
            }
            .navigationTitle("More")
            .themedScreen()
            .sheet(isPresented: $showRepos) { NavigationStack { RepositoriesView() } }
            .fullScreenCover(isPresented: $showGuide) { OnboardingView { showGuide = false } }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }
}
