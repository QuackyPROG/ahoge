import SwiftUI

enum UpdatesPrefs {
    /// Mihon shows three months of updates.
    static var cutoff: Date { Date().addingTimeInterval(-90 * 86_400) }
}

/// Mihon's Updates: chapters library refreshes found, newest first, by day.
struct UpdatesView: View {
    @EnvironmentObject private var repo: LibraryRepository
    @EnvironmentObject private var sources: SourceManager
    @EnvironmentObject private var updater: LibraryUpdater
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.palette) private var palette
    @AppStorage(Pref.updatesLastSeen.name) private var lastSeen = 0.0
    @State private var reading: UpdateEntry?
    @State private var visible = false
    @State private var selecting = false
    @AppStorage(Pref.downloadedOnly.name) private var downloadedOnly = false
    @State private var selection = Set<String>()

    var body: some View {
        let all = repo.updates(since: UpdatesPrefs.cutoff)
        let entries = downloadedOnly ? all.filter { downloads.isDownloaded($0.chapter.key) } : all
        NavigationStack {
            List(selection: $selection) {
                Section {
                    Text(lastUpdatedText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .themedRows(plain: true)
                ForEach(DateGrouping.group(entries, by: \.date), id: \.day) { group in
                    Section {
                        ForEach(group.items) { entry in
                            HStack(spacing: 4) {
                                UpdateRow(manga: entry.manga, chapter: entry.chapter, headers: referer(entry.manga)) { reading = entry }
                                    .allowsHitTesting(!selecting)
                                if !selecting { ChapterDownloadButton(chapter: entry.chapter) }
                            }
                            .tag(entry.id)
                            .swipeActions(edge: .leading) {
                                Button(entry.chapter.read ? "Unread" : "Read", systemImage: entry.chapter.read ? "eye.slash" : "eye") {
                                    repo.setRead([entry.chapter], !entry.chapter.read)
                                }
                                // UIKit draws swipe labels white and dark-mode primaries are pastels, so use the light primary.
                                .tint(Color(uiColor: UIColor(rgb: palette.primary.light)))
                            }
                            .contextMenu {
                                Button("Select", systemImage: "checkmark.circle") {
                                    selection = [entry.id]
                                    withAnimation { selecting = true }
                                }
                                Button("Mark previous as read", systemImage: "arrow.down.to.line") {
                                    repo.markPreviousRead(entry.chapter, in: entry.manga)
                                }
                                if downloads.isDownloaded(entry.chapter.key) {
                                    Button("Delete download", systemImage: "trash", role: .destructive) { downloads.delete([entry.chapter]) }
                                } else {
                                    Button("Download", systemImage: "arrow.down.circle") { downloads.enqueue([entry.chapter]) }
                                }
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
                    ContentUnavailableView("No recent updates", systemImage: "bell", description: Text("Pull down to check your library for new chapters."))
                        .allowsHitTesting(false)
                }
            }
            .environment(\.editMode, .constant(selecting ? .active : .inactive))
            .navigationTitle(selecting ? "\(selection.count) selected" : "Updates")
            .refreshable { await updater.update(repo.library, repo: repo, sources: sources) }
            .toolbar {
                if selecting {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { endSelection() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        let all = Set(entries.map(\.id))
                        Button(selection == all ? "Deselect all" : "Select all") { selection = selection == all ? [] : all }
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Update library", systemImage: "arrow.clockwise") {
                            Task { await updater.update(repo.library, repo: repo, sources: sources) }
                        }
                        .disabled(updater.isRunning)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { if selecting { selectionBar(entries) } }
            .overlay(alignment: .bottom) {
                if updater.isRunning {
                    Label("Updating library… \(updater.done)/\(updater.total)", systemImage: "arrow.clockwise")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding()
                }
            }
            .themedScreen()
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
            .fullScreenCover(item: $reading) { entry in
                ReaderView(sourceId: entry.manga.sourceId, manga: entry.manga, chapter: entry.chapter)
            }
            .onAppear { visible = true; lastSeen = Date().timeIntervalSince1970 }
            .onDisappear { visible = false; lastSeen = Date().timeIntervalSince1970 }
            .onChange(of: updater.lastUpdated) { if visible { lastSeen = Date().timeIntervalSince1970 } }
        }
    }

    private func selectionBar(_ entries: [UpdateEntry]) -> some View {
        let chosen = entries.filter { selection.contains($0.id) }.map(\.chapter)
        return HStack {
            Button("Download", systemImage: "arrow.down.circle") {
                // Oldest first, the order they are read in.
                downloads.enqueue(chosen.reversed())
                endSelection()
            }
            Spacer()
            Button("Delete", systemImage: "trash") {
                downloads.delete(chosen)
                endSelection()
            }
            Spacer()
            Button("Read", systemImage: "eye") {
                repo.setRead(chosen, true)
                endSelection()
            }
            Spacer()
            Button("Unread", systemImage: "eye.slash") {
                repo.setRead(chosen, false)
                endSelection()
            }
        }
        .labelStyle(SelectionBarLabelStyle())
        .disabled(chosen.isEmpty)
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func endSelection() {
        selection = []
        withAnimation { selecting = false }
    }

    private var lastUpdatedText: String {
        guard let date = updater.lastUpdated else { return "Library never updated" }
        return "Library last updated \(date.formatted(.relative(presentation: .named)))"
    }

    private func referer(_ manga: LibraryManga) -> [String: String] {
        sources.installed(manga.sourceId).map { ["Referer": $0.baseUrl + "/"] } ?? [:]
    }
}

private struct UpdateRow: View {
    let manga: LibraryManga
    @ObservedObject var chapter: ChapterRecord
    let headers: [String: String]
    let open: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: Route.manga(manga.ref)) {
                RemoteImage(url: manga.coverUrl, headers: headers, maxPixelWidth: 150)
                    .frame(width: 44, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(manga.title)")
            Button(action: open) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(manga.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(chapter.name).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                        if !chapter.read, chapter.lastPageRead > 0 {
                            Text("Page \(chapter.lastPageRead + 1)").font(.caption).foregroundStyle(palette.primary.color)
                        }
                    }
                    Spacer(minLength: 0)
                    if !chapter.read {
                        Circle().fill(palette.primary.color).frame(width: 8, height: 8)
                    }
                }
                .opacity(chapter.read ? 0.5 : 1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

private struct SelectionBarLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 3) {
            configuration.icon.font(.title3)
            configuration.title.font(.caption2)
        }
    }
}
