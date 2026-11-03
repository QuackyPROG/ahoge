import SwiftUI

/// Picks what to carry from a library entry to another source's copy, then migrates or copies.
/// The new entry's details and chapters are fetched first, so read state can be matched.
struct MigrateSheet: View {
    let old: LibraryManga
    let target: MangaRef
    /// Called with the new entry after it is saved.
    var onDone: (MangaRef) -> Void = { _ in }
    @EnvironmentObject private var repo: LibraryRepository
    @EnvironmentObject private var sources: SourceManager
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss
    @State private var options = MigrateOptions()
    @State private var fetched: LibraryManga?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    entry(old.title, source: sources.installed(old.sourceId)?.name ?? old.sourceId, icon: "arrow.up.circle")
                    entry(target.title, source: sources.installed(target.sourceId)?.name ?? target.sourceId, icon: "arrow.down.circle.fill")
                }
                .themedRows()
                Section("Carry over") {
                    Toggle("Chapters (read and bookmarks)", isOn: $options.chapters)
                    Toggle("Categories", isOn: $options.categories)
                    Toggle("Notes", isOn: $options.notes)
                    Toggle("Custom cover", isOn: $options.customCover)
                    if downloads.downloadedCount(mangaKey: old.key) > 0 {
                        Toggle("Delete downloads of the old entry", isOn: $options.deleteDownloads)
                    }
                }
                .themedRows()
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        Button("Retry") { Task { await load() } }
                    }
                    .themedRows()
                } else if fetched == nil {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Fetching chapters…").foregroundStyle(.secondary)
                        }
                    }
                    .themedRows()
                }
                Section {
                    Button("Migrate") { finish(removeOld: true) }
                    Button("Copy") { finish(removeOld: false) }
                } footer: {
                    Text("Migrate takes the old entry out of your library. Copy keeps both.")
                }
                .disabled(fetched == nil)
                .themedRows()
            }
            .themedScreen()
            .navigationTitle("Migrate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task { if fetched == nil { await load() } }
        }
    }

    private func entry(_ title: String, source: String, icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(2)
                Text(source).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
        }
    }

    private func load() async {
        error = nil
        do {
            let source = try sources.source(target.sourceId)
            let details = try await source.details(url: target.url)
            let chapters = try await source.chapters(url: target.url)
            let saved = repo.upsert(sourceId: target.sourceId, url: target.url, details: details)
            repo.applyChapters(chapters, to: saved)
            fetched = saved
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func finish(removeOld: Bool) {
        guard let fetched else { return }
        var options = options
        options.removeOld = removeOld
        if options.deleteDownloads { downloads.delete(old.chapters) }
        repo.migrate(old, to: fetched, options: options)
        dismiss()
        onDone(fetched.ref)
    }
}

/// More → Migrate: sources with titles in the library, then their titles (Mihon's source migration).
struct MigrateSourcesView: View {
    @EnvironmentObject private var repo: LibraryRepository
    @EnvironmentObject private var sources: SourceManager

    var body: some View {
        let counts = Dictionary(grouping: repo.library, by: \.sourceId).mapValues(\.count)
        let ids = counts.keys.sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }
        List {
            if ids.isEmpty {
                ContentUnavailableView("Nothing to migrate", systemImage: "arrow.left.arrow.right", description: Text("Titles in your library show here by source."))
            }
            Section {
                ForEach(ids, id: \.self) { id in
                    NavigationLink { MigrateTitlesView(sourceId: id) } label: {
                        HStack(spacing: 12) {
                            RemoteImage(url: sources.installed(id)?.iconURL ?? "")
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name(id))
                                if sources.installed(id) == nil {
                                    Text("Not installed").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("\(counts[id] ?? 0)").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
            .themedRows()
        }
        .navigationTitle("Migrate")
        .navigationBarTitleDisplayMode(.inline)
        .themedScreen()
    }

    private func name(_ id: String) -> String { sources.installed(id)?.name ?? id }
}

private struct MigrateTitlesView: View {
    let sourceId: String
    @EnvironmentObject private var repo: LibraryRepository
    @EnvironmentObject private var sources: SourceManager

    var body: some View {
        let titles = repo.library.filter { $0.sourceId == sourceId }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        List {
            ForEach(titles) { manga in
                NavigationLink(value: Route.migrate(manga.ref)) {
                    HStack(spacing: 12) {
                        RemoteImage(url: manga.displayCover)
                            .frame(width: 40, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(manga.title).lineLimit(2)
                    }
                }
            }
            .themedRows()
        }
        .navigationTitle(sources.installed(sourceId)?.name ?? sourceId)
        .navigationBarTitleDisplayMode(.inline)
        .themedScreen()
    }
}
