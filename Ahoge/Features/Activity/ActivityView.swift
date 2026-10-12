// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var model: AppModel

    private var recentUpdates: [UpdateFeedItem] {
        Array(model.updateFeed(searchText: "", downloadedOnly: false).prefix(4))
    }

    private var recentHistory: [(HistoryEntry, Manga, Chapter)] {
        Array(model.historyEntries(searchText: "").prefix(4))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AhogeLayout.sectionSpacing) {
                HStack(spacing: 12) {
                    activityDestination(
                        title: "Updates",
                        subtitle: model.unreadUpdatesCount > 0 ? "\(model.unreadUpdatesCount) new" : "Library feed",
                        systemImage: "sparkles.rectangle.stack"
                    ) {
                        UpdatesView()
                    }

                    activityDestination(
                        title: "History",
                        subtitle: "Reading activity",
                        systemImage: "clock.arrow.circlepath"
                    ) {
                        HistoryView()
                    }

                    activityDestination(
                        title: "Downloads",
                        subtitle: model.downloadJobs.isEmpty ? "Offline titles" : "\(model.downloadJobs.count) queued",
                        systemImage: "arrow.down.circle"
                    ) {
                        DownloadsView()
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    AhogeSectionHeader("Recent updates") {
                        NavigationLink("See All") { UpdatesView() }
                            .font(.subheadline.weight(.semibold))
                    }

                    if recentUpdates.isEmpty {
                        compactEmptyState("No updates yet", systemImage: "sparkles")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(recentUpdates.enumerated()), id: \.offset) { index, item in
                                NavigationLink {
                                    MangaDetailView(manga: item.manga)
                                } label: {
                                    updateRow(item)
                                }
                                .buttonStyle(.plain)
                                if index < recentUpdates.count - 1 { Divider().padding(.leading, 74) }
                            }
                        }
                        .padding(.horizontal, 12)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AhogeLayout.cardRadius, style: .continuous))
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    AhogeSectionHeader("Recently read") {
                        NavigationLink("See All") { HistoryView() }
                            .font(.subheadline.weight(.semibold))
                    }

                    if recentHistory.isEmpty {
                        compactEmptyState("Nothing read yet", systemImage: "book.closed")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(recentHistory.enumerated()), id: \.offset) { index, item in
                                let (entry, manga, chapter) = item
                                NavigationLink {
                                    ReaderView(manga: manga, initialChapter: chapter)
                                } label: {
                                    historyRow(entry: entry, manga: manga, chapter: chapter)
                                }
                                .buttonStyle(.plain)
                                if index < recentHistory.count - 1 { Divider().padding(.leading, 74) }
                            }
                        }
                        .padding(.horizontal, 12)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AhogeLayout.cardRadius, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, AhogeLayout.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .navigationTitle("Activity")
    }

    private func activityDestination<Destination: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer(minLength: 4)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
            .padding(12)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func updateRow(_ item: UpdateFeedItem) -> some View {
        HStack(spacing: 12) {
            MangaCoverView(
                manga: item.manga,
                hideSensitiveCover: model.state.securityPreferences.hideSensitiveCovers,
                allowsAdultContent: model.source(for: item.manga.sourceID)?.allowsAdultContent ?? false
            )
            .frame(width: 50, height: 68)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.manga.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(item.chapter.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(item.chapter.releaseDate, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if item.chapter.isDownloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Downloaded")
            }
        }
        .padding(.vertical, 10)
    }

    private func historyRow(entry: HistoryEntry, manga: Manga, chapter: Chapter) -> some View {
        HStack(spacing: 12) {
            MangaCoverView(
                manga: manga,
                hideSensitiveCover: model.state.securityPreferences.hideSensitiveCovers,
                allowsAdultContent: model.source(for: manga.sourceID)?.allowsAdultContent ?? false
            )
            .frame(width: 50, height: 68)

            VStack(alignment: .leading, spacing: 4) {
                Text(manga.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(chapter.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(entry.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
    }

    private func compactEmptyState(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 82)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: AhogeLayout.cardRadius, style: .continuous))
    }
}
