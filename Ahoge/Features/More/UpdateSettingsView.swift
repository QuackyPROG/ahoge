import SwiftUI

/// Mihon's library update settings: which titles are refreshed, and when.
struct UpdateSettingsView: View {
    @EnvironmentObject private var repo: LibraryRepository
    @AppStorage(Pref.updateSkipUnread.name) private var skipUnread = Pref.updateSkipUnread.defaultValue
    @AppStorage(Pref.updateSkipUnstarted.name) private var skipUnstarted = Pref.updateSkipUnstarted.defaultValue
    @AppStorage(Pref.updateSkipCompleted.name) private var skipCompleted = Pref.updateSkipCompleted.defaultValue
    @AppStorage(Pref.updateSmart.name) private var smart = Pref.updateSmart.defaultValue
    @AppStorage(Pref.updateRefreshMetadata.name) private var refreshMetadata = Pref.updateRefreshMetadata.defaultValue

    @AppStorage(Pref.autoUpdateInterval.name) private var interval = Pref.autoUpdateInterval.defaultValue
    @AppStorage(Pref.autoUpdateOnlyCharging.name) private var onlyCharging = Pref.autoUpdateOnlyCharging.defaultValue

    @AppStorage(Pref.updateNotify.name) private var notify = Pref.updateNotify.defaultValue
    @AppStorage(Pref.updateHideNotificationContent.name) private var hideContent = Pref.updateHideNotificationContent.defaultValue
    @AppStorage(Pref.updatesBadge.name) private var badge = Pref.updatesBadge.defaultValue

    private static let intervalHours = [0, 6, 12, 24, 48, 168]

    private static func label(_ hours: Int) -> String {
        switch hours {
        case 0: "Off"
        case 168: "Every week"
        case 24: "Every day"
        case 48: "Every 2 days"
        default: "Every \(hours) hours"
        }
    }

    var body: some View {
        List {
            Section {
                Picker(selection: $interval) {
                    ForEach(Self.intervalHours, id: \.self) { Text(Self.label($0)).tag($0) }
                } label: {
                    Label { Text("Automatic updates") } icon: { SettingsIcon(systemName: "clock.arrow.2.circlepath", color: .orange) }
                }
                if interval > 0 {
                    Toggle(isOn: $onlyCharging) {
                        Label { Text("Only while charging") } icon: { SettingsIcon(systemName: "bolt.fill", color: .green) }
                    }
                }
            } footer: {
                Text("iOS decides when the app gets to run in the background, so updates can come later than the interval, or be skipped when the device is low on power or the app is rarely opened. Opening the app and pulling down always works.")
            }
            .themedRows()

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

            Section {
                Toggle(isOn: $notify) {
                    Label { Text("Notify about new chapters") } icon: { SettingsIcon(systemName: "bell.badge.fill", color: .red) }
                }
                if notify {
                    Toggle(isOn: $hideContent) {
                        Label { Text("Hide notification content") } icon: { SettingsIcon(systemName: "eye.slash.fill", color: .gray) }
                    }
                }
                Toggle(isOn: $badge) {
                    Label { Text("Unseen updates badge") } icon: { SettingsIcon(systemName: "app.badge.fill", color: .blue) }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("A notification for each title with new chapters after an update. Hidden content leaves out the title and chapter names. The badge counts new chapters since you last opened Updates, on the tab and the app icon. Notifications are allowed in iOS Settings.")
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
        .onChange(of: interval) { old, new in
            // Asks for notification permission the first time updates can run unattended.
            if old == 0, new > 0 { UpdateNotifier.requestAuthorization() }
            BackgroundRefresh.schedule()
        }
        .onChange(of: notify) { _, on in if on { UpdateNotifier.requestAuthorization() } }
        .onChange(of: onlyCharging) { BackgroundRefresh.schedule() }
    }
}
