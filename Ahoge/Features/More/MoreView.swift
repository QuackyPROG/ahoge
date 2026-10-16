// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            modesSection
            libraryToolsSection
            applicationSection
            advancedSection
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("More")

    }

    private var modesSection: some View {
        Section {
            modeToggle(title: "Downloaded Only", subtitle: "Show offline content", systemImage: "arrow.down.circle.fill", isOn: Binding(
                get: { model.state.appSettings.downloadedOnly },
                set: model.setDownloadedOnly
            ))
            modeToggle(title: "Incognito", subtitle: "Pause reading history", systemImage: "eye.slash.fill", isOn: Binding(
                get: { model.state.appSettings.incognitoMode },
                set: model.setIncognitoMode
            ))
        } header: { Text("Reading modes") } footer: {
            Text("Choose what appears in your library and whether reading history is recorded.")
        }
    }

    private var libraryToolsSection: some View {
        Section("Library") {
            NavigationLink { DownloadQueueView() } label: { Label("Download Queue", systemImage: "arrow.down.circle") }
            NavigationLink { DownloadsView() } label: { Label("Downloaded chapters", systemImage: "arrow.down.circle.fill") }
            NavigationLink { CategoryManagementView() } label: { Label("Categories", systemImage: "folder") }
            NavigationLink { LibraryBatchMigrationView() } label: { Label("Migrate library titles", systemImage: "arrow.triangle.swap") }
            NavigationLink { TrackingCenterView() } label: { Label("Tracking", systemImage: "person.badge.clock") }
            NavigationLink { LocalImportsView() } label: { Label("Local imports", systemImage: "internaldrive") }
            NavigationLink { StatsView() } label: { Label("Reading statistics", systemImage: "chart.bar") }
            NavigationLink { DataStorageView() } label: { Label("Data & Storage", systemImage: "externaldrive") }
        }
    }

    private var applicationSection: some View {
        Section("App preferences") {
            NavigationLink { SettingsHomeView() } label: { Label("Settings", systemImage: "gearshape") }
            NavigationLink { SourcesView() } label: { Label("Sources", systemImage: "globe") }
            NavigationLink { SourceCatalogView() } label: { Label("Source catalog", systemImage: "shippingbox") }
        }
    }

    private var advancedSection: some View {
        Section("Support & About") {
            NavigationLink { DiagnosticsLogView() } label: { Label("Error Logs", systemImage: "exclamationmark.bubble") }
            NavigationLink { NativeUpdateView() } label: { Label("App Updates", systemImage: "arrow.triangle.2.circlepath") }
            NavigationLink { AboutView() } label: { Label("About", systemImage: "info.circle") }
            NavigationLink { AhogeHelpView() } label: { Label("Help & setup", systemImage: "questionmark.circle") }
            LabeledContent("Donations", value: "Unavailable")

        }
    }

    private func modeToggle(title: String, subtitle: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage).foregroundStyle(model.chromeTint)
                    .frame(width: 24).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.body)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(minHeight: 44)
    }
}

struct AhogeHelpView: View {
    var body: some View {
        List {
            Section("Set up your library") {
                NavigationLink("Choose sources") { SourcesView() }
                NavigationLink("Source repositories") { SourceReposView() }
                NavigationLink("Import local files") { LocalImportsView() }
                NavigationLink("Restore an Ahoge backup") { RestoreBackupView() }
            }
            Section("Reading & data") {
                Text("Add a title to Library from its details page. Use Updates for new chapters and History to resume reading.")
                NavigationLink("Reader preferences") { ReaderSettingsView() }
                NavigationLink("Download Queue") { DownloadQueueView() }
                NavigationLink("Create a backup") { CreateBackupView() }
            }
            Section("Troubleshooting") {
                Text("If a source is unavailable, cached metadata and downloaded chapters remain accessible. Re-enable the source or migrate the title from its details page.")
                NavigationLink("Error Logs") { DiagnosticsLogView() }
                NavigationLink("App Updates") { NativeUpdateView() }
            }
        }.navigationTitle("Help & Setup")
    }
}
