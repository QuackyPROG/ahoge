// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

private enum DownloadsSegment: String, CaseIterable, Identifiable {
    case queue = "Queue"
    case downloaded = "Downloaded"
    var id: String { rawValue }
}

struct DownloadsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var segment: DownloadsSegment = .downloaded

    var body: some View {
        Group {
            switch segment {
            case .queue:
                DownloadQueueView(showsNavigationTitle: false)
            case .downloaded:
                DownloadedTitlesView()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Read anywhere").font(.headline)
                Picker("Downloads", selection: $segment) {
                ForEach(DownloadsSegment.allCases) { segment in
                    Text(segment.rawValue).tag(segment)
                }
            }
                }
            .pickerStyle(.segmented)
            .padding(.horizontal, AhogeLayout.pagePadding)
            .padding(.vertical, 10)
            .background(AhogePalette.canvas)
        }
        .navigationTitle("Downloads")
        .onAppear {
            if !model.downloadJobs.isEmpty { segment = .queue }
        }
    }
}

private struct DownloadedTitlesView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct DownloadedTitle: Identifiable, Hashable {
        var id: String { manga.id }
        let manga: Manga
        let downloadedCount: Int
        let activeJobsCount: Int
    }

    private var items: [DownloadedTitle] {
        let persistedByID = Dictionary(uniqueKeysWithValues: model.state.persistedMangas.map { ($0.id, $0) })
        let candidates = model.chapterCache.compactMap { (mangaID, chapters) -> DownloadedTitle? in
            let downloadedCount = chapters.filter(\.isDownloaded).count
            guard downloadedCount > 0, let manga = persistedByID[mangaID] else { return nil }
            let activeJobsCount = model.downloadJobs.filter {
                $0.mangaID == mangaID &&
                $0.sourceID == manga.sourceID &&
                ($0.state == .queued || $0.state == .downloading || $0.state == .paused || $0.state == .failed)
            }.count
            return DownloadedTitle(manga: manga, downloadedCount: downloadedCount, activeJobsCount: activeJobsCount)
        }
        return candidates.sorted { $0.manga.title.localizedCaseInsensitiveCompare($1.manga.title) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            if items.isEmpty {
                ContentUnavailableView(
                    "No downloads yet",
                    systemImage: "arrow.down.circle",
                    description: Text("Downloaded chapters stay available here even if a title isn't in your Library.")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 70)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    AhogeSectionHeader("Offline shelf", subtitle: "Chapters stored on this device")
                        .padding(.vertical, 24)
                    LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                              ? [GridItem(.flexible())]
                              : [GridItem(.adaptive(minimum: 132), spacing: 20)],
                              alignment: .leading, spacing: 24) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        NavigationLink {
                            MangaDetailView(manga: item.manga)
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                MangaCoverView(
                                    manga: item.manga,
                                    hideSensitiveCover: model.state.securityPreferences.hideSensitiveCovers,
                                    allowsAdultContent: model.source(for: item.manga.sourceID)?.allowsAdultContent ?? false,
                                    cornerRadius: AhogeLayout.coverRadius
                                )
                                .aspectRatio(AhogeLayout.compactCoverRatio, contentMode: .fit)
                                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 180 : .infinity)
                                .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.manga.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("\(item.downloadedCount) chapter\(item.downloadedCount == 1 ? "" : "s") downloaded")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if item.activeJobsCount > 0 {
                                        Text("\(item.activeJobsCount) active in queue")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                            .accessibilityElement(children: .combine)
                        }
                        .buttonStyle(.plain)

                    }
                    }
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AhogeLayout.pagePadding)
                .padding(.bottom, 28)
            }
        }
    }
}
