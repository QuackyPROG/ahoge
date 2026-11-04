import SwiftUI

/// Mihon's download settings: network, format, automatic removal and automatic downloads.
struct DownloadSettingsView: View {
    @EnvironmentObject private var repo: LibraryRepository
    @EnvironmentObject private var downloads: DownloadManager
    @AppStorage(Pref.downloadOnlyOnWiFi.name) private var onlyOnWiFi = true
    @AppStorage(Pref.saveAsCBZ.name) private var saveAsCBZ = false
    @AppStorage(Pref.downloadConcurrentSources.name) private var concurrentSources = 2
    @AppStorage(Pref.downloadConcurrentPages.name) private var concurrentPages = 3
    @AppStorage(Pref.removeAfterMarkedRead.name) private var removeAfterMarkedRead = false
    @AppStorage(Pref.removeAfterReading.name) private var removeAfterReading = 0
    @AppStorage(Pref.removeBookmarkedToo.name) private var removeBookmarked = false
    @AppStorage(Pref.downloadAhead.name) private var downloadAhead = 0
    @AppStorage(Pref.downloadNewChapters.name) private var downloadNew = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: $onlyOnWiFi) {
                    Label { Text("Only on Wi-Fi") } icon: { SettingsIcon(systemName: "wifi", color: .blue) }
                }
                Toggle(isOn: $saveAsCBZ) {
                    Label { Text("Save as CBZ archive") } icon: { SettingsIcon(systemName: "doc.zipper", color: .brown) }
                }
                Stepper(value: $concurrentSources, in: 1...5) {
                    Label { Text("Sources at once: \(concurrentSources)") } icon: { SettingsIcon(systemName: "square.stack.3d.up.fill", color: .indigo) }
                }
                Stepper(value: $concurrentPages, in: 1...8) {
                    Label { Text("Pages at once: \(concurrentPages)") } icon: { SettingsIcon(systemName: "doc.on.doc.fill", color: .teal) }
                }
            } header: {
                Text("Downloads")
            } footer: {
                Text("Each source downloads one chapter at a time. Downloaded chapters are not included in device backups.")
            }
            .themedRows()

            Section("Delete chapters") {
                Toggle(isOn: $removeAfterMarkedRead) {
                    Label { Text("After manually marked as read") } icon: { SettingsIcon(systemName: "checkmark.circle.fill", color: .green) }
                }
                Picker(selection: $removeAfterReading) {
                    Text("Off").tag(0)
                    Text("Last read chapter").tag(1)
                    Text("Second to last").tag(2)
                    Text("Third to last").tag(3)
                    Text("Fourth to last").tag(4)
                    Text("Fifth to last").tag(5)
                } label: {
                    Label { Text("After reading") } icon: { SettingsIcon(systemName: "book.closed.fill", color: .orange) }
                }
                Toggle(isOn: $removeBookmarked) {
                    Label { Text("Delete bookmarked chapters") } icon: { SettingsIcon(systemName: "bookmark.fill", color: .red) }
                }
            }
            .themedRows()

            Section {
                Toggle(isOn: $downloadNew) {
                    Label { Text("Download new chapters") } icon: { SettingsIcon(systemName: "arrow.down.circle.fill", color: .blue) }
                }
                if downloadNew, !repo.categories.isEmpty {
                    ForEach(repo.categories) { category in
                        Toggle(category.name, isOn: Binding(
                            get: { category.flags & DownloadRules.excludedCategoryFlag == 0 },
                            set: { repo.setCategoryFlag(category.id, mask: DownloadRules.excludedCategoryFlag, on: !$0) }
                        ))
                    }
                }
                Picker(selection: $downloadAhead) {
                    Text("Off").tag(0)
                    ForEach([2, 3, 5, 10], id: \.self) { Text("Next \($0) unread").tag($0) }
                } label: {
                    Label { Text("Download ahead") } icon: { SettingsIcon(systemName: "forward.fill", color: .purple) }
                }
            } header: {
                Text("Automatic downloads")
            } footer: {
                Text("New chapters download after a library update, for titles in the categories turned on here. Download ahead works while reading a downloaded chapter of a library title when the next one is downloaded too.")
            }
            .themedRows()
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .themedScreen()
        .onChange(of: onlyOnWiFi) { downloads.networkPolicyChanged() }
    }
}
