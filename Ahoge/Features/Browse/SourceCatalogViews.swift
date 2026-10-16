// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

//
//  SourceCatalogViews.swift
//  Ahoge
//

import SwiftUI

struct SourceCatalogView: View {
    @EnvironmentObject private var model: AppModel
    @State private var trustedOnly = false
    @State private var selectedLanguageFilter = "preferred"

    private var items: [SourceCatalogItem] {
        model.catalogItems(matchingLanguageFilter: selectedLanguageFilter)
            .filter { !trustedOnly || $0.isTrusted }
    }

    var body: some View {
        List {
            Section("Catalog filters") {
                Toggle("Trusted only", isOn: $trustedOnly)

                Picker("Language Filter", selection: $selectedLanguageFilter) {
                    ForEach(model.sourceCatalogLanguageFilters(), id: \.id) { filter in
                        Text(filter.title).tag(filter.id)
                    }
                }

                NavigationLink {
                    SourceReposView()
                } label: {
                    Label("Repository URLs", systemImage: "link")
                }
            }

            Section("Catalog Packages") {
                if items.isEmpty {
                    ContentUnavailableView("No matching packages", systemImage: "shippingbox", description: Text("Adjust trust or language filters to see available packages."))
                }
                ForEach(items) { item in
                    NavigationLink {
                        SourceCatalogDetailView(item: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.headline).fixedSize(horizontal: false, vertical: true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.supportStatus.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(badgeColor(for: item.supportStatus))
                                if item.hasUpdate {
                                    Label("Update available", systemImage: "arrow.down.circle")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.orange)
                                }
                            }
                            Text(item.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("v\(item.version) • \(item.originLabel) • \(item.isInstalled ? "Installed" : "Available")")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Extensions")
    }
}

struct SourceCatalogDetailView: View {
    @EnvironmentObject private var model: AppModel
    let item: SourceCatalogItem
    @State private var consent = false
    @State private var errorMessage: String?
    @State private var uninstalling = false

    private var current: SourceCatalogItem { model.sourceCatalogItems().first(where: { $0.id == item.id }) ?? item }

    var body: some View {
        List {
            Section {
                Label(current.title, systemImage: "shippingbox")
                    .font(.title2.weight(.bold))
                Text(current.summary).font(.body).foregroundStyle(.secondary)
            }
            Section("Package details") {
                LabeledContent("Version", value: current.version)
                LabeledContent("Trust", value: current.isTrusted ? "Trusted" : "Untrusted")
                LabeledContent("Status", value: current.isInstalled ? "Installed" : "Available")
                LabeledContent("Runtime", value: current.supportStatus.title)
                LabeledContent("Origin", value: current.originLabel)
                if !current.languageCodes.isEmpty {
                    LabeledContent("Languages", value: current.languageCodes.map(model.languageFilterTitle(for:)).joined(separator: ", "))
                }
            }

            if !current.originLabel.contains("Built-in") {
                Section("Package actions") {
                    let installation = model.packageInstallation(current.id)
                    if installation?.trusted != true {
                        Toggle("I trust this repository's source definitions", isOn: $consent)
                        Text("Source definitions control requests and parsing. HTTPS protects transport; it does not certify the publisher.").font(.footnote)
                    }
                    Button(current.hasUpdate ? "Install available update" : installation == nil ? "Install package" : "Trust and enable package") {
                        do { try model.installPackage(current.id, trustConsent: consent); errorMessage = nil }
                        catch { errorMessage = error.localizedDescription }
                    }.disabled(installation?.trusted != true && !consent)
                    if let installation, installation.trusted {
                        Button(installation.enabled ? "Disable package" : "Enable package") { model.setPackageEnabled(current.id, enabled: !installation.enabled) }
                        LabeledContent("Installed version", value: installation.package.version)
                    }
                    if installation != nil { Button("Uninstall package", role: .destructive) { uninstalling = true } }
                    Text("Disable or uninstall preserves library, history and offline files for recovery.").font(.footnote)
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            Section("Included Sources") {
                ForEach(current.sources) { source in
                    NavigationLink {
                        SourcePreferencesView(source: source)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(source.name, systemImage: source.systemImage)
                            Text(model.descriptor(for: source.id)?.engineFamily.title ?? source.engineFamily.title)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(current.title)
        .confirmationDialog("Uninstall this source package?", isPresented: $uninstalling, titleVisibility: .visible) {
            Button("Uninstall", role: .destructive) { model.uninstallPackage(current.id) }
        }
    }
}

struct SourcePreferencesView: View {
    @EnvironmentObject private var model: AppModel

    let source: Source

    var body: some View {
        List {
            Section {
                Label(source.name, systemImage: source.systemImage).font(.title2.weight(.bold))
                Text(source.summary).font(.subheadline).foregroundStyle(.secondary)
                LabeledContent("Language", value: source.language.rawValue)
            }
            Section("Local source choices") {
                Toggle("Enabled", isOn: Binding(get: { model.sourceIsEnabled(source) }, set: { model.setSourceEnabled(source, enabled: $0) }))
                Toggle("Pinned", isOn: Binding(get: { model.sourceIsPinned(source) }, set: { model.setSourcePinned(source, pinned: $0) }))
            }
            Section("Source information") {
                ForEach(model.sourcePreferences(for: source)) { preference in
                    LabeledContent(preference.title, value: preference.value)
                }
            }
            if let descriptor = model.descriptor(for: source.id) {
                Section("Runtime Descriptor") {
                    LabeledContent("Family", value: descriptor.engineFamily.title)
                    LabeledContent("Runtime", value: descriptor.supportStatus.title)
                    if let baseURL = descriptor.baseURL {
                        LabeledContent("Base URL", value: baseURL)
                    }
                    if let packageName = descriptor.packageName {
                        LabeledContent("Package", value: packageName)
                    }
                    if let version = descriptor.version {
                        LabeledContent("Version", value: version)
                    }
                    LabeledContent("Capabilities", value: descriptor.capabilities.map(\.rawValue).sorted().joined(separator: ", "))
                    if !descriptor.featureFlags.isEmpty {
                        LabeledContent("Feature Flags", value: descriptor.featureFlags.joined(separator: ", "))
                    }
                }

                if !descriptor.filterSchema.isEmpty {
                    Section("Filter Schema") {
                        ForEach(descriptor.filterSchema) { filter in
                            LabeledContent(filter.title, value: filter.kind)
                        }
                    }
                }
            }

        }
        .navigationTitle("\(source.name) Settings")
    }
}

struct SourceReposView: View {
    @EnvironmentObject private var model: AppModel
    @State private var repoURL = ""
    @State private var editingRepo: SourceRepoRecord?
    @State private var replacementURL = ""
    @State private var removingRepo: SourceRepoRecord?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        List {
            Section {
                Label("Source repositories", systemImage: "link").font(.title3.weight(.semibold))
                Text("Add a repository URL to import its source definitions. Each repository shows its last refresh and any import errors.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Add Repository") {
                TextField("https://repo.example.com/index.json", text: $repoURL)
                    .keyboardType(.URL)
                    .accessibilityLabel("Repository URL")
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Add Repo") {
                    let value = repoURL
                    repoURL = ""
                    Task {
                        await model.addSourceRepo(value)
                    }
                }
                .disabled(repoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.importingRepoURL != nil)

                if let importing = model.importingRepoURL {
                    LabeledContent("Importing", value: importing)
                        .font(.footnote)
                }

                if let error = model.repoImportErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Current Repositories") {
                if !model.repoRecords.isEmpty {
                    Button("Refresh All") {
                        Task {
                            await model.refreshAllSourceRepos()
                        }
                    }
                    .disabled(model.importingRepoURL != nil)
                }

                ForEach(model.repoRecords) { repo in
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(repo.title)
                                    .font(.headline)
                                Text(repo.url)
                                    .textSelection(.enabled)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Text("\(repo.importedSources.count) imported source(s)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            let actionLayout = dynamicTypeSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                : AnyLayout(HStackLayout(spacing: 16))
                            actionLayout {
                            Button {
                                Task {
                                    await model.refreshSourceRepo(repo.url)
                                }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .frame(minHeight: 44)
                            .accessibilityLabel("Refresh \(repo.title)")
                            .disabled(model.importingRepoURL != nil)

                            Button("Change URL") { editingRepo = repo; replacementURL = repo.url }
                            Button(role: .destructive) {
                                removingRepo = repo
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .frame(minHeight: 44)
                            .accessibilityLabel("Remove \(repo.title)")
                            }
                        }

                        if let error = repo.lastError {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        } else {
                            let liveCount = repo.importedSources.filter { $0.supportStatus == .live }.count
                            let plannedCount = repo.importedSources.filter { $0.supportStatus == .planned }.count
                            Text("\(liveCount) live • \(plannedCount) planned • Updated \(repo.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Source Repos")
        .alert("Change Repository URL", isPresented: Binding(get: { editingRepo != nil }, set: { if !$0 { editingRepo = nil } })) {
            TextField("HTTPS repository URL", text: $replacementURL)
            Button("Save") { if let editingRepo { Task { await model.changeSourceRepoURL(editingRepo.url, to: replacementURL) } }; editingRepo = nil }
            Button("Cancel", role: .cancel) { editingRepo = nil }
        } message: { Text("The old repository remains intact if the new URL cannot be validated. New packages require explicit trust and installation.") }
        .confirmationDialog("Remove this repository?", isPresented: Binding(get: { removingRepo != nil }, set: { if !$0 { removingRepo = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) { if let removingRepo { model.removeSourceRepo(removingRepo.url) }; removingRepo = nil }
        }
    }
}

private func badgeColor(for status: SourceSupportStatus) -> Color {
    switch status {
    case .live:
        return .green
    case .planned:
        return .orange
    case .unsupported:
        return .red
    }
}

struct SourceWebView: View {
    @EnvironmentObject private var model: AppModel
    let source: Source

    var body: some View {
        List {
            Section {
                Label(source.name, systemImage: source.systemImage).font(.title2.weight(.bold))
                Text(source.summary).font(.subheadline).foregroundStyle(.secondary)
            }
            Section("External Browser") {
                if let url = model.sourceWebURL(for: source) {
                    Link(destination: url) {
                        Label("Open \(source.name)", systemImage: "safari").frame(minHeight: 44)
                    }
                    Text(url.host ?? url.absoluteString)
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("Website unavailable", systemImage: "safari", description: Text("This source has no website address available."))
                }
            }

            Section("Compatibility") {
                Text("The source opens in your browser. Sign-in and verification follow the source website’s available options.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Web Source")
    }
}
