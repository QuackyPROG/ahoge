// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

//
//  MigrationViews.swift
//  Ahoge
//

import SwiftUI

struct MigrationSourcesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section {
                Label("Choose a source", systemImage: "globe").font(.title2.weight(.bold))
                Text("Compare titles across available remote catalogs.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            let remoteSources = model.visibleSources.filter { $0.kind == .remote }
            if remoteSources.isEmpty {
                ContentUnavailableView("No remote sources", systemImage: "globe", description: Text("Choose an available source in Explore before comparing titles."))
            }
            ForEach(remoteSources) { source in
                NavigationLink {
                    MigrationSearchView(source: source)
                } label: {
                    SourceRow(source: source)
                }
            }
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("Migrate Source")
    }
}

struct MigrationSearchView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let source: Source
    @State private var query = ""

    private var mangas: [Manga] {
        model.mangas(for: source).filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        let hideSensitiveCovers = model.state.securityPreferences.hideSensitiveCovers

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                SourceRow(source: source)
                Text("Select a title to review its migration candidates.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if mangas.isEmpty {
                    ContentUnavailableView("No matching titles", systemImage: "books.vertical", description: Text("Try another title or browse the source catalog first."))
                } else {
                    LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 132), spacing: 16)], alignment: .leading, spacing: 24) {
                        ForEach(mangas) { manga in
                            NavigationLink {
                                MigrationConfirmationView(source: source, target: manga)
                            } label: {
                                AhogeMangaGridCard(manga: manga, hideSensitiveCover: hideSensitiveCovers, allowsAdultContent: model.source(for: manga.sourceID)?.allowsAdultContent ?? false, badgeText: source.name)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(AhogeLayout.pagePadding)
        }
        .searchable(text: $query, prompt: "Find target title")
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("Search \(source.name)")
    }
}

struct MigrationConfirmationView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let source: Source
    let target: Manga

    var body: some View {
        let hideSensitiveCovers = model.state.securityPreferences.hideSensitiveCovers

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                Text("Your selected title").font(.title2.weight(.bold))
                MangaRow(manga: target, hideSensitiveCover: hideSensitiveCovers, allowsAdultContent: model.source(for: target.sourceID)?.allowsAdultContent ?? false)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Alternative editions").font(.title2.weight(.bold))
                    Text("Check the artwork, title, and source before opening transfer options.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if model.migrationCandidates(for: target).isEmpty {
                    ContentUnavailableView("No migration candidates", systemImage: "arrow.triangle.swap", description: Text("No alternative titles are available in the current catalogs."))
                }
                LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 132), spacing: 16)], alignment: .leading, spacing: 24) {
                    ForEach(model.migrationCandidates(for: target)) { candidate in
                        NavigationLink {
                            MigrationConfigView(source: candidate.source, target: candidate.manga)
                        } label: {
                            AhogeMangaGridCard(manga: candidate.manga, hideSensitiveCover: hideSensitiveCovers, allowsAdultContent: candidate.source.allowsAdultContent, badgeText: candidate.source.name)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(AhogeLayout.pagePadding)
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("Confirm Migration")
    }
}

struct MigrationConfigView: View {
    let source: Source
    let target: Manga

    @State private var transferReading = true
    @State private var transferCategories = true
    @State private var transferTracking = true
    @State private var transferHistory = true

    var body: some View {
        Form {
            Section {
                Label(target.title, systemImage: "book.closed").font(.title2.weight(.bold))
                LabeledContent("Source", value: source.name)
                LabeledContent("Manga", value: target.title)
            }

            Section("Transfer") {
                Toggle("Reading progress", isOn: $transferReading)
                Toggle("Categories", isOn: $transferCategories)
                Toggle("Tracking", isOn: $transferTracking)
                Toggle("History", isOn: $transferHistory)
            }
            Section {
                Label("Configuration preview", systemImage: "info.circle")
                Text("Transfer options can be reviewed here. Applying a migration is not available in this screen.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("Migration Config")
    }
}
