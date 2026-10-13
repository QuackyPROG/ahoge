// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

//
//  TrackingViews.swift
//  Ahoge
//

import SwiftUI

struct TrackingCenterView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section {
                Label("Reading trackers", systemImage: "person.badge.clock").font(.title2.weight(.bold))
                Text("Review which services have title bindings. Link or unlink a service from a manga's tracking screen.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(TrackerService.allCases) { service in
                LabeledContent {
                    Text(model.bindings().contains(where: { $0.service == service }) ? "In use" : "Available")
                } label: { Label(service.rawValue, systemImage: service.systemImage) }
            }
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("Tracking")
    }
}

struct MangaTrackingView: View {
    @EnvironmentObject private var model: AppModel
    let manga: Manga

    var body: some View {
        List {
            Section {
                Text(manga.title).font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                Text("Manage tracker bindings for this title.").font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Linked services") {
                if model.trackerBindings(for: manga).isEmpty {
                    ContentUnavailableView("No linked services", systemImage: "person.badge.clock", description: Text("Choose a tracker below to add a binding for this title."))
                } else {
                    ForEach(model.trackerBindings(for: manga)) { binding in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(binding.service.rawValue, systemImage: binding.service.systemImage)
                                .font(.headline)
                            Text("\(binding.status) • \(binding.progressText)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                model.unlinkTracker(binding)
                            } label: {
                                Label("Unlink", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section("Add Tracker") {
                ForEach(TrackerService.allCases) { service in
                    Button {
                        model.linkTracker(service: service, to: manga)
                    } label: {
                        Label(service.rawValue, systemImage: service.systemImage).frame(minHeight: 44)
                    }
                }
            }

            Section("Search") {
                NavigationLink {
                    TrackerSearchView(manga: manga)
                } label: {
                    Label("Search trackers", systemImage: "magnifyingglass")
                }
            }
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("Tracking")
    }
}

struct TrackerSearchView: View {
    let manga: Manga
    @State private var query = ""

    var body: some View {
        List {
            Section {
                Text(manga.title).font(.title2.weight(.bold))
                Label("Title preview", systemImage: "magnifyingglass")
                Text("This screen previews your search title for each service. Remote search results are not available here.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(TrackerService.allCases) { service in
                VStack(alignment: .leading, spacing: 4) {
                    Label(service.rawValue, systemImage: service.systemImage)
                        .font(.headline)
                    Text(query.isEmpty ? manga.title : query)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $query, prompt: "Search tracker title")
        .listStyle(.insetGrouped)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("Tracker Search")
    }
}
