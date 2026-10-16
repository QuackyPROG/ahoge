// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    @State private var clear = false
    @State private var titleToRemove: Manga?
    @State private var categoryManga: Manga?
    private var entries: [HistoryEntry] {
        model.state.history.sorted { $0.timestamp > $1.timestamp }.filter { entry in search.isEmpty || model.allMangaByID()[entry.mangaID]?.title.localizedCaseInsensitiveContains(search) == true }
    }
    private var days: [Date] { Array(Set(entries.map { Calendar.current.startOfDay(for: $0.timestamp) })).sorted(by: >) }
    var body: some View {
        List {
            if entries.isEmpty { ContentUnavailableView("No matching history", systemImage: "clock", description: Text("Read chapters to build your history, or change your search.")) }
            ForEach(days, id: \.self) { day in
                Section(day.formatted(date: .complete, time: .omitted)) {
                    ForEach(entries.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: day) }) { entry in
                        if let manga = model.allMangaByID()[entry.mangaID] {
                            HStack(spacing: 12) {
                                NavigationLink { MangaDetailView(manga: manga) } label: {
                                    MangaCoverView(manga: manga, hideSensitiveCover: model.state.securityPreferences.hideSensitiveCovers, allowsAdultContent: model.source(for: manga.sourceID)?.allowsAdultContent ?? false).frame(width: 40, height: 56).accessibilityHidden(true)
                                }.buttonStyle(.plain)
                                NavigationLink {
                                    if let chapter = model.chapter(for: entry.chapterID, in: manga), model.canReadChapter(chapter, manga: manga) { ReaderView(manga: manga, initialChapter: chapter) }
                                    else { MangaDetailView(manga: manga) }
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(manga.title).font(.subheadline.weight(.medium))
                                        Text(model.chapter(for: entry.chapterID, in: manga)?.title ?? "Chapter unavailable · Open title for recovery").font(.caption).foregroundStyle(.secondary)
                                        Text(entry.timestamp.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }.contextMenu {
                                Button(model.isInLibrary(manga) ? "Remove from Library" : "Add to Library") { model.toggleLibrary(manga) }.disabled(model.state.securityPreferences.lockLibraryEdits)
                                if model.isInLibrary(manga) { Button("Categories") { categoryManga = manga }.disabled(model.state.securityPreferences.lockLibraryEdits) }
                                if let source = model.migrationSource(for: manga) { NavigationLink("Migrate") { MigrationConfirmationView(source: source, target: manga) } }
                                Button("Remove this entry", role: .destructive) { model.removeHistoryEntry(entry.id) }
                                Button("Remove all history for title", role: .destructive) { titleToRemove = manga }
                            }
                        } else {
                            VStack(alignment: .leading) { Text("Title unavailable"); Text("Restore source metadata or a backup to recover this history entry.").font(.caption).foregroundStyle(.secondary) }.swipeActions { Button("Remove", role: .destructive) { model.removeHistoryEntry(entry.id) } }
                        }
                    }
                }
            }
        }.listStyle(.plain).navigationTitle("History").searchable(text: $search, prompt: "Search history")
        .sheet(item: $categoryManga) { CollectionCategoryPicker(mangaIDs: [$0.id]) }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Clear", systemImage: "trash") { clear = true }.disabled(model.state.history.isEmpty) } }
        .confirmationDialog("Clear \(model.state.history.count) history entries?", isPresented: $clear) { Button("Clear history", role: .destructive) { model.clearHistory() } } message: { Text("Library titles, resume progress and downloads are retained.") }
        .confirmationDialog("Remove history for \(titleToRemove?.title ?? "title")?", isPresented: Binding(get: { titleToRemove != nil }, set: { if !$0 { titleToRemove = nil } })) { Button("Remove title history", role: .destructive) { if let title = titleToRemove { model.removeHistory(for: title.id) }; titleToRemove = nil } }
    }
}
