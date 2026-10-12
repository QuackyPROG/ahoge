// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

struct UpdatesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""
    @State private var downloadedOnly = false

    var body: some View {
        let items = model.updateFeed(searchText: searchText, downloadedOnly: downloadedOnly)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if items.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No library updates" : "No matching updates",
                        systemImage: "sparkles.rectangle.stack",
                        description: Text(downloadedOnly ? "No downloaded chapters match this filter." : "New chapters for library titles will appear here.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        NavigationLink {
                            MangaDetailView(manga: item.manga)
                        } label: {
                            updateRow(item)
                        }
                        .buttonStyle(.plain)

                        if index < items.count - 1 {
                            Divider().padding(.leading, 84)
                        }
                    }
                }
            }
            .padding(.horizontal, AhogeLayout.pagePadding)
            .padding(.bottom, 28)
        }
        .searchable(text: $searchText, prompt: "Search updates")
        .navigationTitle("Updates")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    downloadedOnly.toggle()
                } label: {
                    Image(systemName: downloadedOnly ? "arrow.down.circle.fill" : "arrow.down.circle")
                }
                .accessibilityLabel(downloadedOnly ? "Show all updates" : "Downloaded only")
                .accessibilityAddTraits(downloadedOnly ? .isSelected : [])

                Menu {
                    Button {
                        model.markAllUpdatesSeen()
                    } label: {
                        Label("Mark All Read", systemImage: "checkmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Update actions")
            }
        }
        .onAppear { markVisible(items) }
        .onChange(of: searchText) { _, _ in
            markVisible(model.updateFeed(searchText: searchText, downloadedOnly: downloadedOnly))
        }
        .onChange(of: downloadedOnly) { _, _ in
            markVisible(model.updateFeed(searchText: searchText, downloadedOnly: downloadedOnly))
        }
    }

    private func updateRow(_ item: UpdateFeedItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            MangaCoverView(
                manga: item.manga,
                hideSensitiveCover: model.state.securityPreferences.hideSensitiveCovers,
                allowsAdultContent: model.source(for: item.manga.sourceID)?.allowsAdultContent ?? false,
                cornerRadius: 12
            )
            .frame(width: 56, height: 78)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.manga.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(item.chapter.releaseDate, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(item.chapter.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if item.chapter.isDownloaded {
                        AhogeStatusBadge(title: "Downloaded", systemImage: "arrow.down.circle.fill")
                    }
                    if item.entry.isBookmarked {
                        AhogeStatusBadge(title: "Library", systemImage: "bookmark.fill")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func markVisible(_ items: [UpdateFeedItem]) {
        model.markUpdatesSeen(items)
    }
}
