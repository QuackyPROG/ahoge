// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.
//
//  SettingsViews.swift
//  Ahoge
//
import SwiftUI
import UIKit

struct SettingsHomeView: View {
    var body: some View {
        List {
            Section {
                settingsLink("Search Settings", systemImage: "magnifyingglass", destination: SettingsSearchView())
            }
            Section("Reading preferences") {
                settingsLink("Library", systemImage: "books.vertical", destination: LibrarySettingsView())
                settingsLink("Reader", systemImage: "book.pages", destination: ReaderSettingsView())
                settingsLink("Downloads", systemImage: "arrow.down.circle", destination: DownloadSettingsView())
                settingsLink("Browse", systemImage: "globe", destination: BrowseSettingsView())
            }
            Section("App & privacy") {
                settingsLink("Appearance", systemImage: "sun.max", destination: AppearanceSettingsView())
                settingsLink("Security", systemImage: "faceid", destination: SecuritySettingsView())
                settingsLink("Data & Storage", systemImage: "externaldrive", destination: DataStorageView())
                settingsLink("Tracking", systemImage: "person.badge.clock", destination: TrackingCenterView())
            }
            Section("Support") {
                settingsLink("Advanced", systemImage: "wrench.and.screwdriver", destination: AdvancedSettingsView())
                settingsLink("About", systemImage: "info.circle", destination: AboutView())
            }
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("Settings")
    }
    @ViewBuilder
    private func settingsLink<Destination: View>(_ title: String, systemImage: String, destination: Destination) -> some View {
        NavigationLink {
            destination
        } label: {
            Label(title, systemImage: systemImage).frame(minHeight: 44)
        }
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject private var model: AppModel
    var focusSetting: String? = nil
    var body: some View {
        ScrollViewReader { proxy in
        Form {
            Section {
                Label("Make yourself at home", systemImage: "sun.max").font(.title3.weight(.semibold))
                Text("Follow your device appearance or choose your preferred appearance.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Appearance") {
                Toggle("Follow System Appearance", isOn: Binding(
                    get: { model.state.appSettings.useSystemColorScheme },
                    set: model.setUseSystemAppearance
                )).id("Follow System Appearance")
                if !model.state.appSettings.useSystemColorScheme {
                    Toggle("Prefer Dark Mode", isOn: Binding(
                        get: { model.state.appSettings.prefersDarkMode },
                        set: model.setDarkModePreferred
                    )).id("Prefer Dark Mode")
                }
            }
            Section("Language") {
                NavigationLink("App Language", destination: AppLanguageView()).id("App Language")
                LabeledContent("Current", value: model.currentLanguageLabel)
            }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("Appearance")
        .onAppear { if let focusSetting { DispatchQueue.main.async { proxy.scrollTo(focusSetting, anchor: .center) } } }
        }
    }
}

struct AppLanguageView: View {
    @EnvironmentObject private var model: AppModel
    private let languages = ["system", "en", "id", "ja"]
    var body: some View {
        List {
            Section {
                Text("Choose the app language").font(.title3.weight(.semibold))
                Text("System Default follows your device language.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(languages, id: \.self) { code in
                Button {
                    model.setAppLanguageCode(code)
                } label: {
                    HStack {
                        Text(code == "system" ? "System Default" : code.uppercased())
                        Spacer()
                        if model.state.appSettings.appLanguageCode == code {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .foregroundStyle(.primary)
                .frame(minHeight: 44)
                .accessibilityAddTraits(model.state.appSettings.appLanguageCode == code ? [.isSelected] : [])
            }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("App Language")
    }
}

struct DownloadSettingsView: View {
    @EnvironmentObject private var model: AppModel
    var focusSetting: String? = nil
    var body: some View {
        ScrollViewReader { proxy in
        Form {
            Section {
                Label("Offline reading", systemImage: "arrow.down.circle").font(.title3.weight(.semibold))
                Text("Choose how chapters join the download queue and which connection can be used.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Queue & connection") {
                Picker("Queue Policy", selection: Binding(
                    get: { model.state.downloadPreferences.queueStrategy },
                    set: model.setDownloadQueueStrategy
                )) {
                    ForEach(DownloadQueueStrategy.allCases) { strategy in
                        Text(strategy.title).tag(strategy)
                    }
                }.id("Queue Policy")
                Toggle("Wi-Fi only", isOn: Binding(
                    get: { model.state.downloadPreferences.wifiOnly },
                    set: model.setDownloadWifiOnly
                )).id("Wi-Fi only")
            }
            Section("Automatic Downloads") {
                Toggle("Auto-download new chapters", isOn: Binding(
                    get: { model.state.downloadPreferences.autoDownloadNewChapters },
                    set: model.setAutoDownloadNewChapters
                )).id("Auto-download new chapters")
                Toggle("Unread chapters only", isOn: Binding(
                    get: { model.state.downloadPreferences.unreadOnly },
                    set: model.setAutoDownloadUnreadOnly
                )).id("Unread chapters only")
                .disabled(!model.state.downloadPreferences.autoDownloadNewChapters)
            }
            Section { Text("New chapters are queued when you refresh Library. Periodic background scheduling is unavailable.").font(.footnote).foregroundStyle(.secondary) }
            Section("On this device") {
                LabeledContent("Storage", value: "App-managed offline files")
                LabeledContent("Local Runtime", value: model.localImportSummary())
            }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("Downloads")
        .onAppear { if let focusSetting { DispatchQueue.main.async { proxy.scrollTo(focusSetting, anchor: .center) } } }
        }
    }
}

struct BrowseSettingsView: View {
    @EnvironmentObject private var model: AppModel
    var focusSetting: String? = nil
    var body: some View {
        ScrollViewReader { proxy in
        Form {
            Section {
                Label("Your source directory", systemImage: "globe").font(.title3.weight(.semibold))
                Text("These filters determine the sources available in Browse and search.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Source Visibility") {
                Toggle("Hide adult sources", isOn: Binding(
                    get: { model.state.browsePreferences.hideAdultSources },
                    set: model.setHideAdultSources
                )).id("Hide adult sources")
                Toggle("Enabled sources only", isOn: Binding(
                    get: { model.state.browsePreferences.enabledSourcesOnly },
                    set: model.setEnabledSourcesOnly
                )).id("Enabled sources only")
                Toggle("Pinned sources only", isOn: Binding(
                    get: { model.state.browsePreferences.pinnedSourcesOnly },
                    set: model.setPinnedSourcesOnly
                )).id("Pinned sources only")
            }
            Section("Languages") {
                ForEach(SourceLanguage.allCases) { language in
                    Toggle(language.rawValue, isOn: Binding(
                        get: { model.state.browsePreferences.enabledLanguages.contains(language) },
                        set: { model.setBrowseLanguage(language, enabled: $0) }
                    ))
                }
            }.id("Languages")
            Section("Catalog") {
                NavigationLink("Source Repositories", destination: SourceReposView()).id("Source Repositories")
                LabeledContent("Visible Sources", value: "\(model.visibleSources.count)")
            }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("Browse")
        .onAppear { if let focusSetting { DispatchQueue.main.async { proxy.scrollTo(focusSetting, anchor: .center) } } }
        }
    }
}

private enum StorageRemoval: String {
    case history = "reading history", progress = "resume progress", notes = "reading notes", images = "image cache", metadata = "source metadata cache", allCaches = "all caches"
    var explanation: String {
        switch self {
        case .history: return "Remove recorded history. Titles, downloads and resume progress remain."
        case .progress: return "Remove saved resume pages. Titles, downloads and history remain."
        case .notes: return "Permanently remove notes for all titles."
        case .images: return "Remove cached cover and page images. Downloads remain; online images load again when needed."
        case .metadata: return "Remove source metadata caches. Sources may need refreshing; original imports and downloaded files remain."
        case .allCaches: return "Remove image, network and source metadata caches. Original imports and downloaded files remain."
        }
    }
}

struct DataStorageView: View {
    @EnvironmentObject private var model: AppModel
    var focusSetting: String? = nil
    @State private var removal: StorageRemoval?
    var body: some View {
        ScrollViewReader { proxy in
        List {
            Section("Storage") {
                LabeledContent("Summary", value: model.storageSummary())
                LabeledContent("Imports", value: model.localImportSummary())
                NavigationLink("Local imports") { LocalImportsView() }
                if let usage = model.storageUsage {
                    LabeledContent("Local import files", value: ByteCountFormatter.string(fromByteCount: usage.importedBytes, countStyle: .file))
                    LabeledContent("Download files", value: ByteCountFormatter.string(fromByteCount: usage.downloadedBytes, countStyle: .file))
                } else { ProgressView("Measuring local storage") }
                LabeledContent("Image Cache", value: ByteCountFormatter.string(fromByteCount: Int64(model.cacheStats.diskImageBytes), countStyle: .file))
                LabeledContent("Metadata Cache", value: ByteCountFormatter.string(fromByteCount: Int64(model.cacheStats.diskMetadataBytes), countStyle: .file))
                LabeledContent("Network Cache", value: ByteCountFormatter.string(fromByteCount: Int64(model.cacheStats.diskNetworkBytes), countStyle: .file))
            }
            Section("Backup") {
                NavigationLink("Create Backup", destination: CreateBackupView()).id("Create Backup")
                NavigationLink("Restore Backup", destination: RestoreBackupView()).id("Restore Backup")
            }
            Section {
                Button("Clear History", role: .destructive) {
                    removal = .history
                }.id("Clear History")
                Button("Clear Reading Progress", role: .destructive) {
                    removal = .progress
                }.id("Clear Reading Progress")
                Button("Clear Notes", role: .destructive) {
                    removal = .notes
                }.id("Clear Notes")
                Button("Clear Image Cache", role: .destructive) {
                    removal = .images
                }.id("Clear Image Cache")
                Button("Clear Source Metadata Cache", role: .destructive) {
                    removal = .metadata
                }.id("Clear Source Metadata Cache")
                Button("Clear All Caches", role: .destructive) {
                    removal = .allCaches
                }.id("Clear All Caches")
            } header: { Label("Remove stored data", systemImage: "trash") } footer: {
                Text("These actions clear the selected records or caches from this device.")
            }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("Data & Storage")
        .task { await model.refreshCacheStats(); await model.refreshStorageUsage() }
        .confirmationDialog("Clear \(removal?.rawValue ?? "data")?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } })) {
            Button("Clear selected data", role: .destructive) {
                guard let removal else { return }
                switch removal {
                case .history: model.clearHistory()
                case .progress: model.clearProgress()
                case .notes: model.clearNotes()
                case .images: Task { await model.clearImageCache() }
                case .metadata: Task { await model.clearSourceMetadataCache() }
                case .allCaches: Task { await model.clearAllCaches() }
                }
                self.removal = nil
            }
        } message: { Text(removal?.explanation ?? "") }
        .onAppear { if let focusSetting { DispatchQueue.main.async { proxy.scrollTo(focusSetting, anchor: .center) } } }
        }
    }
}

struct SecuritySettingsView: View {
    @EnvironmentObject private var model: AppModel
    var focusSetting: String? = nil
    var body: some View {
        ScrollViewReader { proxy in
        Form {
            Section("Reading privacy") {
                Toggle("Incognito Mode", isOn: Binding(
                    get: { model.state.appSettings.incognitoMode },
                    set: model.setIncognitoMode
                )).id("Incognito Mode")
            }
            Section("Device protection") {
                Toggle("Lock with Face ID", isOn: Binding(
                    get: { model.state.securityPreferences.requireBiometricUnlock },
                    set: model.setBiometricUnlockEnabled
                )).id("Lock with Face ID")
                Toggle("Blur in App Switcher", isOn: Binding(
                    get: { model.state.securityPreferences.blurAppSwitcher },
                    set: model.setBlurAppSwitcher
                )).id("Blur in App Switcher")
            }
            Section("Cover privacy") {
                Toggle("Hide Sensitive Covers", isOn: Binding(
                    get: { model.state.securityPreferences.hideSensitiveCovers },
                    set: model.setHideSensitiveCovers
                )).id("Hide Sensitive Covers")
            }
            Section("Library Protection") {
                Toggle("Lock library edits", isOn: Binding(
                    get: { model.state.securityPreferences.lockLibraryEdits },
                    set: model.setLockLibraryEdits
                )).id("Lock library edits")
                Text("When enabled, category editing and quick delete actions are disabled.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("Security")
        .onAppear { if let focusSetting { DispatchQueue.main.async { proxy.scrollTo(focusSetting, anchor: .center) } } }
        }
    }
}

struct AdvancedSettingsView: View {
    @EnvironmentObject private var model: AppModel
    var focusSetting: String? = nil
    var body: some View {
        ScrollViewReader { proxy in
        Form {
            Section {
                Label("Advanced controls", systemImage: "wrench.and.screwdriver").font(.title3.weight(.semibold))
                Text("Adjust reader requests, cache limits, and diagnostic visibility.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Reader Networking") {
                Stepper(
                    "Image prefetch window: \(model.state.advancedPreferences.imagePrefetchCount)",
                    value: Binding(
                        get: { model.state.advancedPreferences.imagePrefetchCount },
                        set: model.setImagePrefetchCount
                    ),
                    in: 0...6
                ).id("Image Prefetch Window")
                Toggle("Aggressive image retry", isOn: Binding(
                    get: { model.state.advancedPreferences.aggressiveImageRetry },
                    set: model.setAggressiveImageRetry
                )).id("Aggressive image retry")
            }
            Section("Cache Limits") {
                Stepper(
                    "Memory cache: \(model.state.advancedPreferences.memoryCacheLimitMB) MB",
                    value: Binding(
                        get: { model.state.advancedPreferences.memoryCacheLimitMB },
                        set: model.setMemoryCacheLimitMB
                    ),
                    in: 20...200,
                    step: 20
                ).id("Memory cache")
                Stepper(
                    "Image count limit: \(model.state.advancedPreferences.imageCacheCountLimit)",
                    value: Binding(
                        get: { model.state.advancedPreferences.imageCacheCountLimit },
                        set: model.setImageCacheCountLimit
                    ),
                    in: 40...200,
                    step: 20
                ).id("Image count limit")
                LabeledContent("In-memory images", value: "\(model.cacheStats.memoryImageCount)")
                LabeledContent("In-memory data", value: "\(model.cacheStats.memoryDataCount)")
            }
            Section("History") {
                Stepper(
                    "History limit: \(model.state.advancedPreferences.historyLimit)",
                    value: Binding(
                        get: { model.state.advancedPreferences.historyLimit },
                        set: model.setHistoryLimit
                    ),
                    in: 20...500,
                    step: 20
                ).id("History Limit")
            }
            Section("Diagnostics") {
                Toggle("Show diagnostics", isOn: Binding(
                    get: { model.state.advancedPreferences.showDiagnostics },
                    set: model.setShowDiagnostics
                )).id("Show diagnostics")
                NavigationLink("Open Error Logs", destination: DiagnosticsLogView()).id("Open Error Logs")
                if model.state.advancedPreferences.showDiagnostics {
                    ForEach(model.diagnosticsSummary(), id: \.self) { line in
                        Text(line)
                            .font(.footnote.monospaced())
                    }
                }
            }
            Section("App State") {
                Button("Show onboarding again") {
                    model.resetOnboarding()
                }.id("Show onboarding again")
            }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("Advanced")
        .onAppear { if let focusSetting { DispatchQueue.main.async { proxy.scrollTo(focusSetting, anchor: .center) } } }
        }
    }
}

struct DiagnosticsLogView: View {
    @EnvironmentObject private var model: AppModel
    private enum DiagnosticsTimeRange: String, CaseIterable, Identifiable {
        case all
        case last24h
        case last7d
        case last30d
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all:
                return "All time"
            case .last24h:
                return "Last 24h"
            case .last7d:
                return "Last 7d"
            case .last30d:
                return "Last 30d"
            }
        }
        var range: ClosedRange<Date>? {
            let now = Date()
            let calendar = Calendar.current
            switch self {
            case .all:
                return nil
            case .last24h:
                return (calendar.date(byAdding: .hour, value: -24, to: now) ?? now)...now
            case .last7d:
                return (calendar.date(byAdding: .day, value: -7, to: now) ?? now)...now
            case .last30d:
                return (calendar.date(byAdding: .day, value: -30, to: now) ?? now)...now
            }
        }
    }
    @State private var clearConfirmation = false
    @State private var query = ""
    @State private var selectedKindRawValue = "all"
    @State private var selectedSeverityRawValue = "all"
    @State private var selectedTimeRange: DiagnosticsTimeRange = .all
    @State private var copyConfirmationMessage: String?
    @State private var preparedJSONFileURL: URL?
    @State private var preparedCSVFileURL: URL?
    private var selectedKind: DiagnosticLogKind? {
        guard selectedKindRawValue != "all" else { return nil }
        return DiagnosticLogKind(rawValue: selectedKindRawValue)
    }
    private var selectedSeverity: DiagnosticSeverity? {
        guard selectedSeverityRawValue != "all" else { return nil }
        return DiagnosticSeverity(rawValue: selectedSeverityRawValue)
    }
    private var filteredEntries: [DiagnosticLogEntry] {
        model.filteredDiagnostics(kind: selectedKind, severity: selectedSeverity, dateRange: selectedTimeRange.range, query: query)
    }
    private var jsonExport: String {
        model.exportDiagnosticsJSON(entries: filteredEntries)
    }
    private var csvExport: String {
        model.exportDiagnosticsCSV(entries: filteredEntries)
    }
    var body: some View {
        List {
            Section("Summary") {
                ForEach(model.diagnosticsSummary(), id: \.self) { line in
                    Text(line)
                        .font(.footnote.monospaced())
                }
            }
            Section("Filter entries") {
                Picker("Kind", selection: $selectedKindRawValue) {
                    Text("All").tag("all")
                    ForEach(DiagnosticLogKind.allCases) { kind in
                        Text(kind.rawValue.capitalized).tag(kind.rawValue)
                    }
                }
                Picker("Severity", selection: $selectedSeverityRawValue) {
                    Text("All").tag("all")
                    ForEach(DiagnosticSeverity.allCases) { severity in
                        Text(severity.rawValue.capitalized).tag(severity.rawValue)
                    }
                }
                Picker("Range", selection: $selectedTimeRange) {
                    ForEach(DiagnosticsTimeRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
            }
            Section("JSON export") {
                Button("Copy JSON Export") {
                    UIPasteboard.general.string = jsonExport
                    copyConfirmationMessage = "Copied JSON export to clipboard."
                }
                ShareLink(item: jsonExport) {
                    Label("Share JSON Export", systemImage: "square.and.arrow.up")
                }
                Button("Prepare JSON File") {
                    preparedJSONFileURL = model.diagnosticsExportFileURL(format: .json, entries: filteredEntries)
                }
                if let preparedJSONFileURL {
                    ShareLink(item: preparedJSONFileURL) {
                        Label("Share JSON File", systemImage: "doc")
                    }
                }
            }
            Section("CSV export") {
                Button("Copy CSV Export") {
                    UIPasteboard.general.string = csvExport
                    copyConfirmationMessage = "Copied CSV export to clipboard."
                }
                ShareLink(item: csvExport) {
                    Label("Share CSV Export", systemImage: "square.and.arrow.up")
                }
                Button("Prepare CSV File") {
                    preparedCSVFileURL = model.diagnosticsExportFileURL(format: .csv, entries: filteredEntries)
                }
                if let preparedCSVFileURL {
                    ShareLink(item: preparedCSVFileURL) {
                        Label("Share CSV File", systemImage: "doc")
                    }
                }
            }
            Section {
                Button("Clear Logs", role: .destructive) {
                    clearConfirmation = true
                }
                .disabled(model.diagnosticLogs.isEmpty)
            } header: { Text("Log maintenance") } footer: { Text("Clearing logs removes the recorded diagnostics from this device.") }
            Section("Entries") {
                if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        model.diagnosticLogs.isEmpty ? "No Error Logs" : "No Matching Logs",
                        systemImage: "checkmark.circle",
                        description: Text(model.diagnosticLogs.isEmpty
                            ? "New source, reader, repo, and security failures will appear here."
                            : "Adjust search or filters to find matching entries.")
                    )
                } else {
                    ForEach(filteredEntries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.title)
                                    .font(.headline)
                                Label(entry.severity.rawValue.capitalized, systemImage: "exclamationmark.circle")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(severityColor(entry.severity))
                                Text(entry.kind.rawValue.capitalized)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if !entry.metadata.isEmpty {
                                ForEach(entry.metadata.keys.sorted(), id: \.self) { key in
                                    if let value = entry.metadata[key] {
                                        LabeledContent(key, value: value)
                                            .font(.footnote.monospaced())
                                    }
                                }
                            }
                            if let errorCode = entry.errorCode {
                                LabeledContent("errorCode", value: errorCode)
                                    .font(.footnote.monospaced())
                            }
                            if let module = entry.module {
                                LabeledContent("module", value: module)
                                    .font(.footnote.monospaced())
                            }
                            if let resolutionHint = entry.resolutionHint {
                                LabeledContent("resolutionHint", value: resolutionHint)
                                    .font(.caption)
                            }
                            Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                                .font(.footnote.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search title, message, metadata")
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("Error Logs")
        .confirmationDialog("Clear \(model.diagnosticLogs.count) diagnostic entries?", isPresented: $clearConfirmation) { Button("Clear logs", role: .destructive) { model.clearDiagnostics() } }
        .alert("Diagnostics Export", isPresented: Binding(
            get: { copyConfirmationMessage != nil },
            set: { if !$0 { copyConfirmationMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                copyConfirmationMessage = nil
            }
        } message: {
            Text(copyConfirmationMessage ?? "")
        }
    }
    private func severityColor(_ severity: DiagnosticSeverity) -> Color {
        switch severity {
        case .critical:
            return .red
        case .error:
            return .orange
        case .warning:
            return .yellow
        case .info:
            return .secondary
        }
    }
}

private enum PreferenceDestination: String, CaseIterable {
    case appearance, language, library, reader, downloads, browse, security, advanced, storage, tracking
}

private struct PreferenceSearchEntry: Identifiable {
    let title: String
    let destination: PreferenceDestination
    var focus: String? = nil
    var id: String { "\(destination.rawValue).\(title)" }
}

struct SettingsSearchView: View {
    @State private var query = ""
    private var entries: [PreferenceSearchEntry] {
        var results: [PreferenceSearchEntry] = []
        let groups: [(PreferenceDestination, [String])] = [
            (.appearance, ["Follow System Appearance", "Prefer Dark Mode"]),
            (.language, ["App Language"]),
            (.library, ["Show Continue Reading", "Show Downloaded Badge", "Show Unread Badge", "Sort", "Default Category"]),
            (.downloads, ["Queue Policy", "Wi-Fi only", "Auto-download new chapters", "Unread chapters only"]),
            (.browse, ["Hide adult sources", "Enabled sources only", "Pinned sources only", "Languages", "Source Repositories"]),
            (.security, ["Incognito Mode", "Lock with Face ID", "Blur in App Switcher", "Hide Sensitive Covers", "Lock library edits"]),
            (.advanced, ["Image Prefetch Window", "Aggressive image retry", "Memory cache", "Image count limit", "History Limit", "Show diagnostics", "Show onboarding again"]),
            (.storage, ["Create Backup", "Restore Backup", "Clear History", "Clear Reading Progress", "Clear Notes", "Clear Image Cache", "Clear Source Metadata Cache", "Clear All Caches"]),
            (.tracking, ["Local tracking status", "Local tracking progress", "Local tracking score", "Remote service availability"]),
        ]
        for (destination, titles) in groups { results += titles.map { PreferenceSearchEntry(title: $0, destination: destination, focus: $0) } }
        let reader: [(String, String)] = [
            ("Reading mode", "mode"), ("Wide pages", "spread"), ("Orientation", "orientation"), ("Image scale", "scale"),
            ("Zoom start", "zoomStart"), ("Tap navigation", "tapNavigation"), ("Invert horizontal taps", "invertHorizontalTaps"),
            ("Invert vertical taps", "invertVerticalTaps"), ("Animate page transitions", "animatePages"), ("Background", "background"),
            ("Crop uniform borders", "cropBorders"), ("Reverse split halves", "invertSplitOrder"), ("Rotate unsplit wide pages", "rotateWidePages"),
            ("Rotate clockwise", "rotateClockwise"), ("Fullscreen", "fullscreen"), ("Long strip page gaps", "continuousGap"), ("Webtoon page gaps", "webtoonGap"),
            ("Side padding", "sidePadding"), ("Double tap to zoom", "doubleTapZoom"), ("Allow zoom below fitted size", "allowZoomOut"),
            ("Show page number", "showPageNumber"), ("Keep screen awake", "keepAwake"), ("Enable color filter", "colorFilter"),
            ("Grayscale", "grayscale"), ("Dimming", "dimming"),
        ]
        results += reader.map { PreferenceSearchEntry(title: $0.0, destination: .reader, focus: "reader." + $0.1) }
        return results
    }
    private var filtered: [PreferenceSearchEntry] { entries.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.destination.rawValue.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        List {
            if filtered.isEmpty { ContentUnavailableView.search(text: query) }
            ForEach(filtered) { entry in
                NavigationLink { destination(entry) } label: {
                    VStack(alignment: .leading, spacing: 3) { Text(entry.title); Text(entry.destination.rawValue.capitalized).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }.searchable(text: $query, prompt: "Find setting").navigationTitle("Search Settings")
    }
    @ViewBuilder private func destination(_ entry: PreferenceSearchEntry) -> some View {
        switch entry.destination {
        case .appearance: AppearanceSettingsView(focusSetting: entry.focus)
        case .language: AppLanguageView()
        case .library: LibrarySettingsView(focusSetting: entry.focus)
        case .reader: ReaderSettingsView(focusSetting: entry.focus)
        case .downloads: DownloadSettingsView(focusSetting: entry.focus)
        case .browse: BrowseSettingsView(focusSetting: entry.focus)
        case .security: SecuritySettingsView(focusSetting: entry.focus)
        case .advanced: AdvancedSettingsView(focusSetting: entry.focus)
        case .storage: DataStorageView(focusSetting: entry.focus)
        case .tracking: TrackingCenterView()
        }
    }
}

struct AboutView: View {
    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (\(build))"
    }
    var body: some View {
        List {
            Section {
                Text("Ahoge").font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("A home for your manga library.").font(.body).foregroundStyle(.secondary)
            }
            Section("Installed app") {
                LabeledContent("Name", value: "Ahoge")
                LabeledContent("Version", value: versionLabel)
                NavigationLink("Open Source Licenses", destination: LicensesView())
            }
            Section("Support") {
                NavigationLink("Help & Setup") { AhogeHelpView() }
                NavigationLink("App Updates") { NativeUpdateView() }
                Text("Website and external documentation links are not configured for this build.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("About")
    }
}

struct LicensesView: View {
    var body: some View {
        List {
            Section("Third-party attribution") {
                NavigationLink("Mihon iOS · Apache License 2.0", destination: LicenseDetailView(title: "Mihon iOS", text: "Portions of Ahoge’s Swift and SwiftUI code were adapted from Mihon iOS. Copyright 2025 Mihon iOS Contributors. Licensed under the Apache License, Version 2.0. Ahoge includes later modifications and additions; this attribution does not imply affiliation. The full license and THIRD_PARTY_NOTICES.md are distributed with the source."))
            }
            Section("System frameworks") {
                NavigationLink("SwiftUI", destination: LicenseDetailView(title: "SwiftUI", text: "Apple UI framework used for the iOS port."))
                NavigationLink("Foundation", destination: LicenseDetailView(title: "Foundation", text: "System framework used for model and persistence plumbing."))
            }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("Licenses")
    }
}

private struct LicenseDetailView: View {
    let title: String
    let text: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(title).font(.title.weight(.bold))
                Text(text).font(.body).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle(title)
    }
}
