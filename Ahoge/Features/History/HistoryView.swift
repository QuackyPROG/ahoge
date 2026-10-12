// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""
    @State private var showClearConfirmation = false

    var body: some View {
        let entries = model.historyEntries(searchText: searchText)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if entries.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No history yet" : "No matching history",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Read a chapter and it will appear here for quick resuming.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, item in
                        let (entry, manga, chapter) = item
                        NavigationLink {
                            ReaderView(manga: manga, initialChapter: chapter)
                        } label: {
                            historyRow(entry: entry, manga: manga, chapter: chapter)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                model.removeHistoryEntry(entry.id)
                            } label: {
                                Label("Remove from History", systemImage: "trash")
                            }
                        }

                        if index < entries.count - 1 {
                            Divider().padding(.leading, 84)
                        }
                    }
                }
            }
            .padding(.horizontal, AhogeLayout.pagePadding)
            .padding(.bottom, 28)
        }
        .searchable(text: $searchText, prompt: "Search history")
        .navigationTitle("History")
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showClearConfirmation = true
                        } label: {
                            Label("Clear History", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("History actions")
                }
            }
        }
        .confirmationDialog("Clear reading history?", isPresented: $showClearConfirmation) {
            Button("Clear History", role: .destructive) { model.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the history list. It does not remove manga from your library or delete downloads.")
        }
    }

    private func historyRow(entry: HistoryEntry, manga: Manga, chapter: Chapter) -> some View {
        HStack(spacing: 14) {
            MangaCoverView(
                manga: manga,
                hideSensitiveCover: model.state.securityPreferences.hideSensitiveCovers,
                allowsAdultContent: model.source(for: manga.sourceID)?.allowsAdultContent ?? false,
                cornerRadius: 12
            )
            .frame(width: 56, height: 78)

            VStack(alignment: .leading, spacing: 5) {
                Text(manga.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(chapter.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityLabel("Resume reading")
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
