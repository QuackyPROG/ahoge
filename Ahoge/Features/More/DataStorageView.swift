import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Backups, caches and cookies (Mihon's "Data and storage").
struct DataStorageView: View {
    @EnvironmentObject private var repo: LibraryRepository
    @EnvironmentObject private var extensions: ExtensionStore
    @EnvironmentObject private var sources: SourceManager
    @State private var exporting: BackupDocument?
    @State private var exportName = ""
    @State private var importing = false
    @State private var restoring = false
    @State private var report: RestoreReport?
    @State private var message: String?

    var body: some View {
        List {
            Section {
                Button(action: createBackup) {
                    Label { Text("Create backup").foregroundStyle(.primary) } icon: { SettingsIcon(systemName: "square.and.arrow.up.fill", color: .blue) }
                }
                Button { importing = true } label: {
                    Label { Text(restoring ? "Restoring…" : "Restore backup").foregroundStyle(.primary) } icon: { SettingsIcon(systemName: "square.and.arrow.down.fill", color: .green) }
                }
                .disabled(restoring)
            } header: {
                Text("Backup")
            } footer: {
                Text("A backup holds your library, categories, reading progress, history, repositories and settings. Restoring merges it into what is already here.")
            }
            .themedRows()

            Section("Storage") {
                Button {
                    Task {
                        await ImageLoader.shared.clear()
                        message = "Image cache cleared."
                    }
                } label: {
                    Label { Text("Clear image cache").foregroundStyle(.primary) } icon: { SettingsIcon(systemName: "photo.stack", color: .gray) }
                }
                Button(role: .destructive) {
                    Task {
                        SharedCookies.removeAll()
                        await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
                        sources.resetSessions()
                        message = "Cookies and website data cleared."
                    }
                } label: {
                    Label { Text("Clear cookies and website data") } icon: { SettingsIcon(systemName: "trash.fill", color: .red) }
                }
            }
            .themedRows()
        }
        .navigationTitle("Data and storage")
        .navigationBarTitleDisplayMode(.inline)
        .themedScreen()
        .fileExporter(
            isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
            document: exporting,
            contentType: .ahogeBackup,
            defaultFilename: exportName
        ) { result in
            if case .failure(let error) = result { message = "Could not save the backup: \(error.localizedDescription)" }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url): Task { await restore(from: url) }
            case .failure(let error): message = error.localizedDescription
            }
        }
        .sheet(item: Binding(get: { report.map(ReportItem.init) }, set: { if $0 == nil { report = nil } })) { item in
            NavigationStack { RestoreReportView(report: item.report) }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func createBackup() {
        let backup = BackupService.snapshot(of: repo, store: extensions, defaults: .standard)
        do {
            exporting = BackupDocument(data: try BackupCodec.encode(backup))
            exportName = BackupFile.name(at: backup.createdAt)
        } catch {
            message = "Could not create the backup: \(error.localizedDescription)"
        }
    }

    private func restore(from url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        restoring = true
        defer { restoring = false }
        do {
            let backup = try BackupCodec.decode(try Data(contentsOf: url))
            report = await BackupService.restore(backup, into: repo, store: extensions, defaults: .standard)
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct ReportItem: Identifiable, Equatable {
    let report: RestoreReport
    var id: String { "report" }
}

/// Mihon's restore dialog: what came back and what could not.
struct RestoreReportView: View {
    let report: RestoreReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Label("\(report.restoredManga) title\(report.restoredManga == 1 ? "" : "s") restored", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .themedRows()
            if !report.missingSources.isEmpty {
                Section {
                    ForEach(report.missingSources, id: \.self) { Text($0) }
                } header: {
                    Text("Sources not installed")
                } footer: {
                    Text("These titles are in your library, but you need to add a repository that has these sources before you can read them.")
                }
                .themedRows()
            }
            if !report.failedRepos.isEmpty {
                Section("Repositories that could not be added") {
                    ForEach(report.failedRepos, id: \.self) { Text($0).font(.footnote) }
                }
                .themedRows()
            }
        }
        .navigationTitle("Restore finished")
        .navigationBarTitleDisplayMode(.inline)
        .themedScreen()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
