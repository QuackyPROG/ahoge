// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var model: AppModel
    @State private var blockedLinkMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AhogeLayout.sectionSpacing) {
                modesSection
                libraryToolsSection
                applicationSection
                advancedSection
            }
            .padding(.horizontal, AhogeLayout.pagePadding)
            .padding(.vertical, 12)
        }
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
        VStack(alignment: .leading, spacing: 12) {
            AhogeSectionHeader("Quick Modes", subtitle: "Temporary ways to change what Ahoge shows and records.")
            HStack(spacing: 12) {
                modeToggle(
                    title: "Downloaded Only",
                    subtitle: "Show offline content",
                    systemImage: "arrow.down.circle.fill",
                    isOn: Binding(
                        get: { model.state.appSettings.downloadedOnly },
                        set: model.setDownloadedOnly
                    )
                )
                modeToggle(
                    title: "Incognito",
                    subtitle: "Pause reading history",
                    systemImage: "eye.slash.fill",
                    isOn: Binding(
                        get: { model.state.appSettings.incognitoMode },
                        set: model.setIncognitoMode
                    )
                )
            }
        }
    }

    private var libraryToolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AhogeSectionHeader("Library & Data")
            VStack(spacing: 0) {
                NavigationLink { DownloadsView() } label: {
                    AhogeActionRow(title: "Downloads", subtitle: "Queue and offline chapters", systemImage: "arrow.down.circle")
                }
                Divider().padding(.leading, 48)
                NavigationLink { CategoryManagementView() } label: {
                    AhogeActionRow(title: "Categories", subtitle: "Organize your library", systemImage: "folder")
                }
                Divider().padding(.leading, 48)
                NavigationLink { StatsView() } label: {
                    AhogeActionRow(title: "Stats", subtitle: "Reading and library metrics", systemImage: "chart.bar")
                }
                Divider().padding(.leading, 48)
                NavigationLink { DataStorageView() } label: {
                    AhogeActionRow(title: "Data & Storage", subtitle: "Backups, cache, and storage", systemImage: "externaldrive")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: AhogeLayout.cardRadius, style: .continuous))
        }
    }

    private var applicationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AhogeSectionHeader("Application")
            VStack(spacing: 0) {
                NavigationLink { SettingsHomeView() } label: {
                    AhogeActionRow(title: "Settings", subtitle: "Reader, library, sources, and privacy", systemImage: "gearshape")
                }
                Divider().padding(.leading, 48)
                NavigationLink { NativeUpdateView() } label: {
                    AhogeActionRow(title: "App Updates", subtitle: "Check the installed Ahoge build", systemImage: "arrow.triangle.2.circlepath")
                }
                Divider().padding(.leading, 48)
                NavigationLink { AboutView() } label: {
                    AhogeActionRow(title: "About", subtitle: "Version, licenses, and project information", systemImage: "info.circle")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: AhogeLayout.cardRadius, style: .continuous))
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AhogeSectionHeader("Support & Advanced")
            VStack(spacing: 0) {
                NavigationLink { DiagnosticsLogView() } label: {
                    AhogeActionRow(title: "Error Logs", subtitle: "Diagnostics for troubleshooting", systemImage: "exclamationmark.bubble")
                }
                Divider().padding(.leading, 48)
                Button {
                    blockedLinkMessage = "Help belum siap. Tautan eksternal masih ditutup sementara."
                } label: {
                    AhogeActionRow(title: "Help", subtitle: "Support resources", systemImage: "questionmark.circle", showsChevron: false)
                }
                Divider().padding(.leading, 48)
                Button {
                    blockedLinkMessage = "Donate belum siap. Tautan eksternal masih ditutup sementara."
                } label: {
                    AhogeActionRow(title: "Donate", subtitle: "Support Ahoge development", systemImage: "heart.circle", showsChevron: false)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: AhogeLayout.cardRadius, style: .continuous))
        }
    }

    private func modeToggle(
        title: String,
        subtitle: String,
        systemImage: String,
        isOn: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(model.chromeTint)
                Spacer()
                Toggle(title, isOn: isOn)
                    .labelsHidden()
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: AhogeLayout.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
