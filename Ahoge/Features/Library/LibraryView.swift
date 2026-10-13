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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedCategoryID: String?
    @State private var searchText = ""
    @State private var sortMode: LibrarySortMode = .recent
    @State private var quickReadTarget: QuickReadTarget?

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 160 : 132), spacing: 16, alignment: .top)]
    }

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
                        Text("Your reading room")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
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

                if continueItems.count > 1 {
                    VStack(alignment: .leading, spacing: 12) {
                        AhogeSectionHeader("Recently read")
                        if dynamicTypeSize.isAccessibilitySize {
                            ForEach(Array(continueItems.dropFirst())) { item in
                                NavigationLink { MangaDetailView(manga: item.manga) } label: {
                                    recentTitle(item, hideSensitiveCovers: hideSensitiveCovers)
                                }.buttonStyle(.plain)
                            }
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 16) {
                                    ForEach(Array(continueItems.dropFirst())) { item in
                                        NavigationLink { MangaDetailView(manga: item.manga) } label: {
                                            recentTitle(item, hideSensitiveCovers: hideSensitiveCovers).frame(width: 132)
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }

                if !model.categories.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Browse your shelves").font(.subheadline).foregroundStyle(.secondary)
                        ScrollView(dynamicTypeSize.isAccessibilitySize ? .vertical : .horizontal, showsIndicators: false) {
                            (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))) {
                                AhogeFilterChip("All", systemImage: "square.grid.2x2", isSelected: selectedCategoryID == nil) {
                                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { selectedCategoryID = nil }
                                }
                                ForEach(model.categories) { category in
                                    AhogeFilterChip(
                                        category.name,
                                        systemImage: category.systemImage,
                                        isSelected: selectedCategoryID == category.id
                                    ) {
                                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { selectedCategoryID = category.id }
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
                            Label(searchText.isEmpty && selectedCategoryID == nil ? "Your collection starts here" : "No matching titles", systemImage: "books.vertical")
                        } description: {
                            Text(searchText.isEmpty && selectedCategoryID == nil ? "Open the Explore tab, choose a source, and add a title to your Library." : "Try another search or return to all shelves.")
                        } actions: {
                            if !searchText.isEmpty || selectedCategoryID != nil {
                                Button("Show All Titles") { searchText = ""; selectedCategoryID = nil }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                    } else {
                        LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : columns, alignment: .leading, spacing: 24) {
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
            .frame(maxWidth: 1200, alignment: .leading)
            .padding(.horizontal, horizontalSizeClass == .regular ? 28 : AhogeLayout.pagePadding)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(AhogePalette.canvas)
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
                    Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Library actions")
            }
        }
    }

    private func recentTitle(_ item: LibraryManga, hideSensitiveCovers: Bool) -> some View {
        AhogeMangaGridCard(
            manga: item.manga,
            hideSensitiveCover: hideSensitiveCovers,
            allowsAdultContent: model.source(for: item.manga.sourceID)?.allowsAdultContent ?? false,
            progress: item.progress
        )
    }

    private func unreadBadge(for item: LibraryManga) -> String? {
        guard let latest = item.latestChapter else { return nil }
        if item.progress == nil { return "New" }
        if item.progress?.chapterID != latest.id { return "New" }
        return nil
    }
}
