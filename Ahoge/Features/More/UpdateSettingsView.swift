import SwiftUI

/// Mihon's library update settings: which titles are refreshed, and when.
struct UpdateSettingsView: View {
    @EnvironmentObject private var repo: LibraryRepository
    @AppStorage(Pref.updateSkipUnread.name) private var skipUnread = Pref.updateSkipUnread.defaultValue
    @AppStorage(Pref.updateSkipUnstarted.name) private var skipUnstarted = Pref.updateSkipUnstarted.defaultValue
    @AppStorage(Pref.updateSkipCompleted.name) private var skipCompleted = Pref.updateSkipCompleted.defaultValue
    @AppStorage(Pref.updateSmart.name) private var smart = Pref.updateSmart.defaultValue
    @AppStorage(Pref.updateRefreshMetadata.name) private var refreshMetadata = Pref.updateRefreshMetadata.defaultValue

    var body: some View {
        List {
            Section {
                Toggle(isOn: $smart) {
                    Label { Text("Smart update") } icon: { SettingsIcon(systemName: "calendar.badge.clock", color: .purple) }
                }
                Toggle(isOn: $refreshMetadata) {
                    Label { Text("Refresh metadata") } icon: { SettingsIcon(systemName: "arrow.triangle.2.circlepath", color: .teal) }
                }
            } footer: {
                Text("Smart update checks a title about as often as it releases chapters, from the dates of its latest chapters. Refresh metadata also re-fetches details and the cover when a title updates. Each title can have its own interval on its page.")
            }
            .themedRows()

            Section {
                Toggle(isOn: $skipUnread) {
                    Label { Text("With unread chapters") } icon: { SettingsIcon(systemName: "envelope.badge.fill", color: .orange) }
                }
                Toggle(isOn: $skipUnstarted) {
                    Label { Text("Not started") } icon: { SettingsIcon(systemName: "book.closed.fill", color: .blue) }
                }
                Toggle(isOn: $skipCompleted) {
                    Label { Text("Completed") } icon: { SettingsIcon(systemName: "checkmark.circle.fill", color: .green) }
                }
            } header: {
                Text("Skip titles")
            } footer: {
                Text("Pulling down in the library or Updates checks every title that is not skipped here, whether or not it is due.")
            }
            .themedRows()

            if !repo.categories.isEmpty {
                Section {
                    ForEach(repo.categories) { category in
                        Toggle(category.name, isOn: Binding(
                            get: { category.flags & UpdateRules.excludedCategoryFlag == 0 },
                            set: { repo.setCategoryFlag(category.id, mask: UpdateRules.excludedCategoryFlag, on: !$0) }
                        ))
                    }
                } header: {
                    Text("Categories")
                } footer: {
                    Text("A title in a category turned off here is not updated, even when it is in other categories too.")
                }
                .themedRows()
            }
        }
        .navigationTitle("Library updates")
        .navigationBarTitleDisplayMode(.inline)
        .themedScreen()
    }
}
