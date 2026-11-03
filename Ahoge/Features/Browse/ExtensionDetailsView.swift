import SwiftUI
import WebKit

/// One installed source: what the repository says about it, and the per-source switches
/// (Mihon's extension details).
struct ExtensionDetailsView: View {
    let sourceId: String
    @EnvironmentObject private var store: ExtensionStore
    @EnvironmentObject private var sources: SourceManager
    @Environment(\.dismiss) private var dismiss
    @State private var incognito = false
    @State private var message: String?
    @State private var confirmingUninstall = false

    var body: some View {
        if let item = store.installed.first(where: { $0.id == sourceId }) {
            content(item)
        } else {
            ContentUnavailableView("Not installed", systemImage: "puzzlepiece.extension")
                .themedScreen()
        }
    }

    private func content(_ item: InstalledSource) -> some View {
        let listed = store.indexes[item.repoURL]?.sources.first { $0.id == item.id }
        return List {
            Section {
                HStack(spacing: 14) {
                    RemoteImage(url: item.iconURL ?? "")
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).font(.title3.bold())
                        Text(item.id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                .padding(.vertical, 4)
            }
            .themedRows()

            Section {
                LabeledContent("Version", value: item.version)
                if let listed, listed.version != item.version {
                    LabeledContent("In repository", value: listed.version)
                }
                LabeledContent("Language", value: SourceFilterView.languageName(item.lang))
                LabeledContent("18+", value: item.nsfw ? "Yes" : "No")
                LabeledContent("Repository", value: store.repos.first { $0.url == item.repoURL }?.name ?? item.repoURL)
                LabeledContent("Website", value: URL(string: item.baseUrl)?.host ?? item.baseUrl)
                if let listed {
                    LabeledContent("Health") {
                        Label(Self.healthTitle(listed.health.status), systemImage: listed.isReportedBroken ? "exclamationmark.triangle.fill" : "checkmark.seal")
                            .foregroundStyle(listed.isReportedBroken ? .orange : .secondary)
                    }
                    if let checked = listed.health.checkedAt {
                        LabeledContent("Checked", value: checked)
                    }
                }
            }
            .themedRows()

            Section {
                Toggle(isOn: Binding(get: { incognito }, set: { setIncognito($0) })) {
                    Label("Incognito for this source", systemImage: "eyeglasses")
                }
            } footer: {
                Text("Reading this source saves no progress or history.")
            }
            .themedRows()

            Section {
                Button {
                    Task { await clearCookies(item) }
                } label: {
                    Label("Clear cookies", systemImage: "trash")
                }
                Button(role: .destructive) { confirmingUninstall = true } label: {
                    Label("Uninstall", systemImage: "xmark.bin")
                }
            }
            .themedRows()
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .themedScreen()
        .onAppear { incognito = Pref.incognitoSources.value().contains(item.id) }
        .confirmationDialog("Uninstall \(item.name)?", isPresented: $confirmingUninstall, titleVisibility: .visible) {
            Button("Uninstall", role: .destructive) {
                store.uninstall(item.id)
                sources.resetSessions()
                dismiss()
            }
        } message: {
            Text("Titles from this source stay in your library.")
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    static func healthTitle(_ status: String) -> String {
        switch status {
        case "ok", "working": "Working"
        case "broken": "Reported broken"
        case "unverified": "Not verified"
        default: "Unknown"
        }
    }

    private func setIncognito(_ on: Bool) {
        incognito = on
        var ids = Pref.incognitoSources.value()
        ids.removeAll { $0 == sourceId }
        if on { ids.append(sourceId) }
        Pref.incognitoSources.set(ids)
    }

    /// The source's cookies in the app and in the web view (Cloudflare clearance, logins).
    private func clearCookies(_ item: InstalledSource) async {
        SharedCookies.remove(forBaseURL: item.baseUrl)
        if let host = URL(string: item.baseUrl)?.host?.lowercased() {
            let data = WKWebsiteDataStore.default()
            let records = await data.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
            // Records are named by registrable domain ("example.com" for "www.example.com").
            let matching = records.filter { host == $0.displayName.lowercased() || host.hasSuffix("." + $0.displayName.lowercased()) }
            await data.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: matching)
        }
        sources.resetSession(item.id)
        message = "Cookies for \(item.name) cleared."
    }
}
