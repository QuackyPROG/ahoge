// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

struct GlobalSearchView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), alignment: .top)]
            : [GridItem(.adaptive(minimum: 132), spacing: 16, alignment: .top)]
    }

    var body: some View {
        let results = model.globalSearchResults(query: query)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: AhogeLayout.sectionSpacing) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(query.isEmpty ? "Find your next story" : "Results for \(query)")
                        .font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                    Text("Search your available catalogs by title, author, or genre.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    NavigationLink { SourcesFilterView() } label: {
                        Label("Source selection", systemImage: "line.3.horizontal.decrease.circle")
                            .frame(minHeight: 44)
                    }
                }
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "Search all sources",
                        systemImage: "magnifyingglass",
                        description: Text("Enter a title, author, or genre. Results stay grouped by source so you know where each title comes from.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else if results.isEmpty {
                    ContentUnavailableView(
                        "No results",
                        systemImage: "books.vertical",
                        description: Text("Try a broader query or enable more sources.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    ForEach(results, id: \.0.id) { source, mangas in
                        VStack(alignment: .leading, spacing: 12) {
                            AhogeSectionHeader(source.name, subtitle: "\(mangas.count) result\(mangas.count == 1 ? "" : "s")")
                            if let error = model.sourceError(for: source.id) {
                                Label(error, systemImage: "wifi.exclamationmark")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                ForEach(mangas) { manga in
                                    NavigationLink {
                                        MangaDetailView(manga: manga)
                                    } label: {
                                        AhogeMangaGridCard(
                                            manga: manga,
                                            hideSensitiveCover: model.state.securityPreferences.hideSensitiveCovers,
                                            allowsAdultContent: model.source(for: manga.sourceID)?.allowsAdultContent ?? false,
                                            badgeText: model.isInLibrary(manga) ? "Library" : nil
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button {
                                            model.toggleLibrary(manga)
                                        } label: {
                                            Label(
                                                model.isInLibrary(manga) ? "Remove from Library" : "Add to Library",
                                                systemImage: model.isInLibrary(manga) ? "bookmark.slash" : "bookmark"
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AhogeLayout.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .searchable(text: $query, prompt: "Title, author, or genre")
        .navigationTitle("Search")
    }
}
