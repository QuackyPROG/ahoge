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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Library feed").font(.title2.weight(.bold))
                    Text("The latest chapters from your Library.").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 24)

                AhogeFilterChip("Downloaded chapters", systemImage: "arrow.down.circle", isSelected: downloadedOnly) {
                    downloadedOnly.toggle()
                }
                .padding(.bottom, 16)

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
                        if index == 0 || !Calendar.current.isDate(item.chapter.releaseDate, inSameDayAs: items[index - 1].chapter.releaseDate) {
                            Text(item.chapter.releaseDate.formatted(date: .complete, time: .omitted))
                                .font(.headline).foregroundStyle(.secondary)
                                .padding(.top, 24).padding(.bottom, 8)
                                .accessibilityAddTraits(.isHeader)
                        }
                        NavigationLink {
                            MangaDetailView(manga: item.manga)
                        } label: {
                            if index == 0 { updateFeature(item) }
                            else { updateRow(item) }
                        }
                        .buttonStyle(.plain)

                        if index < items.count - 1 {
                            Divider().padding(.leading, 84)
                        }
                    }
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AhogeLayout.pagePadding)
            .padding(.bottom, 28)
        }
        .searchable(text: $searchText, prompt: "Search updates")
        .navigationTitle("Updates")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
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

    private func updateFeature(_ item: UpdateFeedItem) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) { updateCover(item); updateIdentity(item) }
            VStack(alignment: .leading, spacing: 16) { updateCover(item); updateIdentity(item) }
        }
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open manga and its chapter list")
    }

    private func updateCover(_ item: UpdateFeedItem) -> some View {
        MangaCoverView(
            manga: item.manga,
            hideSensitiveCover: model.state.securityPreferences.hideSensitiveCovers,
            allowsAdultContent: model.source(for: item.manga.sourceID)?.allowsAdultContent ?? false,
            cornerRadius: 12
        )
        .frame(width: 98, height: 140)
        .accessibilityHidden(true)
    }

    private func updateIdentity(_ item: UpdateFeedItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Latest chapter").font(.subheadline).foregroundStyle(.secondary)
            Text(item.manga.title).font(.title2.weight(.bold))
            Text(item.chapter.title).font(.body).foregroundStyle(.secondary)
            if item.chapter.isDownloaded { AhogeStatusBadge(title: "Ready offline", systemImage: "arrow.down.circle.fill") }
            if item.entry.isBookmarked { AhogeStatusBadge(title: "In Library", systemImage: "bookmark.fill") }
            Label("View chapters", systemImage: "arrow.right").font(.headline).foregroundStyle(.tint)
                .frame(minHeight: 44)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func updateRow(_ item: UpdateFeedItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            MangaCoverView(
                manga: item.manga,
                hideSensitiveCover: model.state.securityPreferences.hideSensitiveCovers,
                allowsAdultContent: model.source(for: item.manga.sourceID)?.allowsAdultContent ?? false,
                cornerRadius: AhogeLayout.coverRadius
            )
            .frame(width: 56, height: 80)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.manga.title)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.chapter.releaseDate, style: .relative)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text(item.chapter.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
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
