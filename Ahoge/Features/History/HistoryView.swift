import SwiftUI

/// Mihon's History: the last chapter read of each manga, newest first, by day.
struct HistoryView: View {
    @EnvironmentObject private var repo: LibraryRepository
    @EnvironmentObject private var sources: SourceManager
    @State private var entries: [HistoryEntry] = []
    @State private var search = ""
    @State private var reading: ChapterRecord?
    @State private var target: HistoryEntry?
    @State private var confirmRemove = false
    @State private var confirmClear = false

    var body: some View {
        let shown = search.isEmpty ? entries : entries.filter { $0.manga.title.localizedCaseInsensitiveContains(search) }
        NavigationStack {
            List {
                ForEach(DateGrouping.group(shown, by: \.lastRead), id: \.day) { group in
                    Section {
                        ForEach(group.items) { entry in
                            HistoryRow(entry: entry, headers: referer(entry.manga), resume: { resume(entry) }) {
                                target = entry
                                confirmRemove = true
                            }
                        }
                    } header: {
                        Text(group.title)
                    }
                    .themedRows(plain: true)
                }
            }
            .listStyle(.plain)
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView("Nothing read recently", systemImage: "clock.arrow.circlepath", description: Text("Chapters you read show up here."))
                } else if shown.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .navigationTitle("History")
            .searchable(text: $search)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear history", systemImage: "trash") { confirmClear = true }
                        .disabled(entries.isEmpty)
                }
            }
            .confirmationDialog("Remove from history?", isPresented: $confirmRemove, titleVisibility: .visible, presenting: target) { entry in
                Button("Remove this chapter", role: .destructive) {
                    repo.removeHistory(chapterKey: entry.chapter.key)
                    reload()
                }
                Button("Remove all of \(entry.manga.title)", role: .destructive) {
                    repo.removeHistory(mangaKey: entry.manga.key)
                    reload()
                }
            }
            .confirmationDialog("Clear all history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear history", role: .destructive) {
                    repo.clearHistory()
                    reload()
                }
            } message: {
                Text("Read progress stays as it is.")
            }
            .themedScreen()
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
            .fullScreenCover(item: $reading, onDismiss: reload) { chapter in
                if let manga = chapter.manga { ReaderView(sourceId: manga.sourceId, manga: manga, chapter: chapter) }
            }
            // Reading from another tab changes history; reload whenever this tab shows.
            .onAppear(perform: reload)
        }
    }

    private func reload() { entries = repo.history() }

    /// The same chapter until it is finished, then the next; the last chapter again when none is newer.
    private func resume(_ entry: HistoryEntry) {
        reading = entry.resumeChapter ?? entry.chapter
    }

    private func referer(_ manga: LibraryManga) -> [String: String] {
        sources.installed(manga.sourceId).map { ["Referer": $0.baseUrl + "/"] } ?? [:]
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let headers: [String: String]
    let resume: () -> Void
    let remove: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: Route.manga(entry.manga.ref)) {
                RemoteImage(url: entry.manga.coverUrl, headers: headers, maxPixelWidth: 150)
                    .frame(width: 48, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(entry.manga.title)")
            Button(action: resume) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.manga.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text("\(entry.chapter.name) · \(entry.lastRead.formatted(date: .omitted, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Resume reading")
            Button(action: remove) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove from history")
            Button(action: resume) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.onPrimary.color)
                    .frame(width: 36, height: 36)
                    .background(palette.primary.color, in: Circle())
            }
            .buttonStyle(PressableCardStyle())
            // The row's text button already resumes; one VoiceOver stop is enough.
            .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
    }
}
