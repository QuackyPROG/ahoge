// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

struct LibraryView: View {
    private struct QuickReadTarget: Hashable, Identifiable {
        var id: String { "\(manga.id)::\(chapter.id)" }
        let manga: Manga
        let chapter: Chapter
    }

    @EnvironmentObject private var model: AppModel
    @State private var selectedCategoryID: String?
    @State private var searchText = ""
    @State private var sortMode: LibrarySortMode = .recent
    @State private var quickReadTarget: QuickReadTarget?

    private let columns = [
        GridItem(.adaptive(minimum: 142, maximum: 190), spacing: 16, alignment: .top)
    ]

    private var items: [LibraryManga] {
        model.libraryItems(selectedCategoryID: selectedCategoryID, searchText: searchText, sortMode: sortMode)
    }

    var body: some View {
        let hideSensitiveCovers = model.state.securityPreferences.hideSensitiveCovers
        let continueItems = model.state.libraryPreferences.showContinueReading ? model.continueReadingItems : []

        ScrollView {
            LazyVStack(alignment: .leading, spacing: AhogeLayout.sectionSpacing) {
                if let item = continueItems.first,
                   let chapter = model.startChapter(for: item.manga) {
                    VStack(alignment: .leading, spacing: 12) {
                        AhogeSectionHeader("Pick up where you left off")
                        NavigationLink {
                            ReaderView(manga: item.manga, initialChapter: chapter)
                        } label: {
                            AhogeContinueReadingCard(
                                manga: item.manga,
                                chapter: chapter,
                                progress: item.progress,
                                hideSensitiveCover: hideSensitiveCovers,
                                allowsAdultContent: model.source(for: item.manga.sourceID)?.allowsAdultContent ?? false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !model.categories.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        AhogeSectionHeader("Categories")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                AhogeFilterChip("All", systemImage: "square.grid.2x2", isSelected: selectedCategoryID == nil) {
                                    withAnimation(.snappy) { selectedCategoryID = nil }
                                }
                                ForEach(model.categories) { category in
                                    AhogeFilterChip(
                                        category.name,
                                        systemImage: category.systemImage,
                                        isSelected: selectedCategoryID == category.id
                                    ) {
                                        withAnimation(.snappy) { selectedCategoryID = category.id }
                                    }
                                }
                            }
                        }
                        .contentMargins(.horizontal, 1, for: .scrollContent)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    AhogeSectionHeader(
                        selectedCategoryID.map { model.categoryName(for: $0) } ?? "Your Library",
                        subtitle: items.isEmpty ? nil : "\(items.count) title\(items.count == 1 ? "" : "s")"
                    )

                    if items.isEmpty {
                        ContentUnavailableView {
                            Label(searchText.isEmpty ? "Library is Empty" : "No Matches", systemImage: "books.vertical")
                        } description: {
                            Text(searchText.isEmpty ? "Explore sources and add titles to build your collection." : "Try another title or category.")
                        } actions: {
                            if !searchText.isEmpty {
                                Button("Clear Search") { searchText = "" }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                            ForEach(items) { item in
                                NavigationLink {
                                    MangaDetailView(manga: item.manga)
                                } label: {
                                    AhogeMangaGridCard(
                                        manga: item.manga,
                                        hideSensitiveCover: hideSensitiveCovers,
                                        allowsAdultContent: model.source(for: item.manga.sourceID)?.allowsAdultContent ?? false,
                                        progress: item.progress,
                                        badgeText: unreadBadge(for: item),
                                        showsDownloadedBadge: model.state.libraryPreferences.showDownloadedBadge && model.isTitleDownloaded(manga: item.manga)
                                    )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        if let chapter = model.startChapter(for: item.manga) {
                                            quickReadTarget = QuickReadTarget(manga: item.manga, chapter: chapter)
                                        }
                                    } label: {
                                        Label("Read", systemImage: "book")
                                    }

                                    if !model.state.securityPreferences.lockLibraryEdits {
                                        Button(role: .destructive) {
                                            model.toggleLibrary(item.manga)
                                        } label: {
                                            Label("Remove from Library", systemImage: "trash")
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
        }
        .searchable(text: $searchText, prompt: "Search library")
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(item: $quickReadTarget) { target in
            NavigationStack {
                ReaderView(manga: target.manga, initialChapter: target.chapter)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close", systemImage: "xmark") { quickReadTarget = nil }
                        }
                    }
            }
        }
        .onAppear {
            sortMode = model.preferredLibrarySortMode()
        }
        .onChange(of: sortMode) { _, newValue in
            model.setLibrarySortMode(newValue)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Sort") {
                        Picker("Sort", selection: $sortMode) {
                            ForEach(LibrarySortMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                    }

                    Section("Manage") {
                        NavigationLink {
                            LibrarySettingsView()
                        } label: {
                            Label("Library Settings", systemImage: "slider.horizontal.3")
                        }

                        NavigationLink {
                            CategoryManagementView()
                        } label: {
                            Label("Categories", systemImage: "folder.badge.plus")
                        }

                        NavigationLink {
                            LibraryBatchMigrationView()
                        } label: {
                            Label("Migration", systemImage: "arrow.triangle.swap")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Library actions")
            }
        }
    }

    private func unreadBadge(for item: LibraryManga) -> String? {
        guard let latest = item.latestChapter else { return nil }
        if item.progress == nil { return "New" }
        if item.progress?.chapterID != latest.id { return "New" }
        return nil
    }
}
