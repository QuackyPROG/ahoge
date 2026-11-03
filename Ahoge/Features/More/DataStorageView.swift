import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Backups, caches and cookies (Mihon's "Data and storage").
struct DataStorageView: View {
    @EnvironmentObject private var repo: LibraryRepository
    @EnvironmentObject private var extensions: ExtensionStore
    @EnvironmentObject private var sources: SourceManager
    @EnvironmentObject private var downloads: DownloadManager
    @AppStorage(Pref.clearChapterCacheOnLaunch.name) private var clearChapterCacheOnLaunch = false
    @State private var usage: StorageUsage?
    @AppStorage(Pref.autoBackupInterval.name) private var autoInterval = 0
    @AppStorage(Pref.autoBackupKeep.name) private var autoKeep = 4
    @AppStorage(Pref.autoBackupLast.name) private var autoLast = 0.0
    @State private var exporting: BackupDocument?
    @State private var exportName = ""
    @State private var importing = false
    @State private var restoring = false
    @State private var report: RestoreReport?
    @State private var message: String?
    @State private var confirmResetReader = false

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
                Text("A backup holds your library, categories, reading progress, history, repositories and settings. Restoring merges it into what is already here. Mihon and Tachiyomi backups (.tachibk) work too; their sources are matched by name.")
            }
            .themedRows()

            Section {
                Picker(selection: $autoInterval) {
                    ForEach(BackupSchedule.intervalHours, id: \.self) { Text(Self.intervalLabel($0)).tag($0) }
                } label: {
                    Label { Text("Automatic backup") } icon: { SettingsIcon(systemName: "clock.arrow.2.circlepath", color: .orange) }
                }
                if autoInterval > 0 {
                    Stepper(value: $autoKeep, in: 1...20) {
                        Label { Text("Backups to keep: \(autoKeep)") } icon: { SettingsIcon(systemName: "tray.full.fill", color: .teal) }
                    }
                }
            } footer: {
                if autoInterval > 0 {
                    Text("Saved in the Ahoge folder in the Files app (Backups). \(Self.lastBackupText(autoLast))")
                } else {
                    Text("Backups are made when you leave the app. Sideloaded apps lose their data when they expire or are re-signed, so turn this on and copy the files off the device now and then.")
                }
            }
            .themedRows()

            Section("Library data") {
                NavigationLink { ClearDatabaseView() } label: {
                    Label { Text("Clear database") } icon: { SettingsIcon(systemName: "trash.slash.fill", color: .red) }
                }
                LibraryExportRow()
                Button { confirmResetReader = true } label: {
                    Label { Text("Reset per-series reader settings").foregroundStyle(.primary) } icon: { SettingsIcon(systemName: "arrow.counterclockwise.circle.fill", color: .orange) }
                }
            }
            .themedRows()

            Section("Storage") {
                LabeledContent {
                    Text(usage.map { Self.bytes($0.downloads) } ?? "…")
                } label: {
                    Label { Text("Downloads") } icon: { SettingsIcon(systemName: "arrow.down.circle.fill", color: .blue) }
                }
                Button {
                    Task {
                        await ImageLoader.shared.clear()
                        message = "Image cache cleared."
                        await measure()
                    }
                } label: {
                    LabeledContent {
                        Text(usage.map { Self.bytes($0.imageCache) } ?? "…")
                    } label: {
                        Label { Text("Clear image cache").foregroundStyle(.primary) } icon: { SettingsIcon(systemName: "photo.stack", color: .gray) }
                    }
                }
                Button {
                    downloads.clearChapterCache()
                    message = "Chapter cache cleared."
                    Task { await measure() }
                } label: {
                    LabeledContent {
                        Text(usage.map { Self.bytes($0.chapterCache) } ?? "…")
                    } label: {
                        Label { Text("Clear chapter cache").foregroundStyle(.primary) } icon: { SettingsIcon(systemName: "doc.zipper", color: .brown) }
                    }
                }
                Toggle(isOn: $clearChapterCacheOnLaunch) {
                    Label { Text("Clear chapter cache on launch") } icon: { SettingsIcon(systemName: "arrow.uturn.backward.circle.fill", color: .teal) }
                }
                Button {
                    downloads.reindex()
                    message = "Downloads reindexed."
                    Task { await measure() }
                } label: {
                    Label { Text("Reindex downloads").foregroundStyle(.primary) } icon: { SettingsIcon(systemName: "arrow.triangle.2.circlepath", color: .indigo) }
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
        .task { await measure() }
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
        .confirmationDialog("Reset per-series reader settings?", isPresented: $confirmResetReader, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                let count = PerSeriesReaderSettings.reset()
                message = "Reset \(count) per-series setting\(count == 1 ? "" : "s")."
            }
        } message: {
            Text("Every series goes back to the default reading mode and orientation.")
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private struct StorageUsage {
        let downloads: Int64
        let imageCache: Int64
        let chapterCache: Int64
    }

    private func measure() async {
        let files = await downloads.storageUsage()
        let images = await ImageLoader.shared.diskUsage()
        usage = StorageUsage(downloads: files.downloads, imageCache: Int64(images), chapterCache: files.chapterCache)
    }

    private static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    private static func intervalLabel(_ hours: Int) -> String {
        switch hours {
        case 0: "Off"
        case 6: "Every 6 hours"
        case 12: "Every 12 hours"
        case 24: "Daily"
        case 48: "Every 2 days"
        default: "Weekly"
        }
    }

    private static func lastBackupText(_ seconds: Double) -> String {
        guard seconds > 0 else { return "Last automatically backed up: never" }
        let date = Date(timeIntervalSince1970: seconds)
        return "Last automatically backed up: \(date.formatted(date: .abbreviated, time: .shortened))"
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
            let backup = try BackupService.load(try Data(contentsOf: url), sources: extensions.rows().map { $0.source })
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

/// Saves the library list as a CSV file.
private struct LibraryExportRow: View {
    @EnvironmentObject private var repo: LibraryRepository
    @EnvironmentObject private var extensions: ExtensionStore
    @State private var document: CSVDocument?

    var body: some View {
        Button(action: export) {
            Label { Text("Export library list (CSV)").foregroundStyle(.primary) } icon: { SettingsIcon(systemName: "tablecells.fill", color: .green) }
        }
        .fileExporter(
            isPresented: Binding(get: { document != nil }, set: { if !$0 { document = nil } }),
            document: document,
            contentType: .commaSeparatedText,
            defaultFilename: "ahoge-library"
        ) { _ in }
    }

    private func export() {
        let text = LibraryCSV.make(repo.library) { id in
            extensions.installed.first { $0.id == id }.map { ($0.name, $0.baseUrl) }
        }
        document = CSVDocument(text: text)
    }
}
