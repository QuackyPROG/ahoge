// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var model: AppModel
    @State private var blockedLinkMessage: String?

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
        .alert("Coming Soon", isPresented: Binding(
            get: { blockedLinkMessage != nil },
            set: { if !$0 { blockedLinkMessage = nil } }
        )) {
            Button("OK", role: .cancel) { blockedLinkMessage = nil }
        } message: {
            Text(blockedLinkMessage ?? "")
        }
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
        Section("Library tools") {
            NavigationLink { DownloadsView() } label: { Label("Downloads", systemImage: "arrow.down.circle") }
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
        Section("Advanced & help") {
            NavigationLink { DiagnosticsLogView() } label: { Label("Error Logs", systemImage: "exclamationmark.bubble") }
            NavigationLink { NativeUpdateView() } label: { Label("App Updates", systemImage: "arrow.triangle.2.circlepath") }
            NavigationLink { AboutView() } label: { Label("About", systemImage: "info.circle") }
            Button {
                blockedLinkMessage = "Help belum siap. Tautan eksternal masih ditutup sementara."
            } label: { Label("Help", systemImage: "questionmark.circle").frame(minHeight: 44) }
            .foregroundStyle(.primary)
            Button {
                blockedLinkMessage = "Donate belum siap. Tautan eksternal masih ditutup sementara."
            } label: { Label("Donate", systemImage: "heart.circle").frame(minHeight: 44) }
            .foregroundStyle(.primary)
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
