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
    @AppStorage(Pref.swipeRight.name) private var swipeRight = Pref.swipeRight.defaultValue
    @AppStorage(Pref.swipeLeft.name) private var swipeLeft = Pref.swipeLeft.defaultValue
    @AppStorage(Pref.hideMissingChapters.name) private var hideMissing = false
    @AppStorage(Pref.markDuplicateRead.name) private var markDuplicateRead = false
    @State private var showRepos = false

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
                }
                .themedRows()

                Section("Data") {
                    NavigationLink { DataStorageView() } label: {
                        Label { Text("Data and storage") } icon: { SettingsIcon(systemName: "externaldrive.fill", color: .gray) }
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
                }
                .themedRows()
            }
            .navigationTitle("More")
            .themedScreen()
            .sheet(isPresented: $showRepos) { NavigationStack { RepositoriesView() } }
        }
    }
}
