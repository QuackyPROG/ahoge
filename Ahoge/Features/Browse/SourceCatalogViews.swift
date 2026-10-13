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
            Section {
                Label("Build your source shelf", systemImage: "shippingbox")
                    .font(.title3.weight(.semibold))
                Text("Review package support and included sources before choosing a catalog.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
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
        .navigationTitle("Source Catalog")
    }
}

struct SourceCatalogDetailView: View {
    @EnvironmentObject private var model: AppModel
    let item: SourceCatalogItem

    var body: some View {
        List {
            Section {
                Label(item.title, systemImage: "shippingbox")
                    .font(.title2.weight(.bold))
                Text(item.summary).font(.body).foregroundStyle(.secondary)
            }
            Section("Package details") {
                LabeledContent("Version", value: item.version)
                LabeledContent("Trust", value: item.isTrusted ? "Trusted" : "Untrusted")
                LabeledContent("Status", value: item.isInstalled ? "Installed" : "Available")
                LabeledContent("Runtime", value: item.supportStatus.title)
                LabeledContent("Origin", value: item.originLabel)
                if !item.languageCodes.isEmpty {
                    LabeledContent("Languages", value: item.languageCodes.map(model.languageFilterTitle(for:)).joined(separator: ", "))
                }
            }

            Section("Included Sources") {
                ForEach(item.sources) { source in
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
        .navigationTitle(item.title)
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
            Section("Source Preferences") {
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

                            Button(role: .destructive) {
                                model.removeSourceRepo(repo.url)
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
