// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

struct UpdatesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    @State private var read: CollectionFilter = .any
    @State private var downloaded: CollectionFilter = .any
    @State private var bookmark: CollectionFilter = .any
    @State private var selected = Set<String>()
    @State private var selecting = false
    @State private var deleteConfirmation = false
    @State private var showFilters = false
    private var items: [UpdateFeedItem] {
        model.updateFeed.filter {
            let state = model.chapterState(for: $0.chapter.id, mangaID: $0.manga.id)
            return (search.isEmpty || $0.manga.title.localizedCaseInsensitiveContains(search) || $0.chapter.title.localizedCaseInsensitiveContains(search)) && read.matches(state.isRead) && bookmark.matches(state.isBookmarked) && downloaded.matches(model.isChapterDownloaded(manga: $0.manga, chapter: $0.chapter))
        }
    }
    private var chosen: [UpdateFeedItem] { items.filter { selected.contains($0.id) } }
    var body: some View {
        List {
            if !model.libraryRefreshErrors.isEmpty { Section("Refresh failures") { ForEach(model.libraryRefreshErrors.keys.sorted(), id: \.self) { id in Text(model.libraryRefreshErrors[id] ?? "").font(.caption).foregroundStyle(.secondary) } } }
            if items.isEmpty { ContentUnavailableView("No matching updates", systemImage: "arrow.triangle.2.circlepath", description: Text("Refresh your Library or change the filters.")) }
            ForEach(days, id: \.self) { day in
                Section(day.formatted(date: .complete, time: .omitted)) {
                    ForEach(items.filter { Calendar.current.isDate($0.chapter.releaseDate, inSameDayAs: day) }) { item in
                        HStack(spacing: 12) {
                            if selecting { Button { toggle(item.id) } label: { Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle") }.buttonStyle(.borderless) }
                            NavigationLink { MangaDetailView(manga: item.manga) } label: {
                                MangaCoverView(manga: item.manga, hideSensitiveCover: model.state.securityPreferences.hideSensitiveCovers, allowsAdultContent: model.source(for: item.manga.sourceID)?.allowsAdultContent ?? false).frame(width: 40, height: 56).accessibilityHidden(true)
                            }.buttonStyle(.plain)
                            if selecting { Button { toggle(item.id) } label: { identity(item) }.buttonStyle(.plain) }
                            else if model.canReadChapter(item.chapter, manga: item.manga) { NavigationLink { ReaderView(manga: item.manga, initialChapter: item.chapter) } label: { identity(item) } }
                            else { NavigationLink { MangaDetailView(manga: item.manga) } label: { identity(item) } }
                        }.contextMenu {
                            Button("Select") { selecting = true; selected.insert(item.id) }
                            Button("Mark read") { model.setChaptersRead([item.chapter.id], mangaID: item.manga.id, read: true) }
                            Button("Mark unread") { model.setChaptersRead([item.chapter.id], mangaID: item.manga.id, read: false) }
                            Button("Toggle bookmark") { model.setChaptersBookmarked([item.chapter.id], mangaID: item.manga.id, bookmarked: !model.chapterState(for: item.chapter.id, mangaID: item.manga.id).isBookmarked) }
                            Button("Download") { model.enqueueDownload(manga: item.manga, chapter: item.chapter) }.disabled(item.manga.sourceID == "local-files" || model.isChapterDownloaded(manga: item.manga, chapter: item.chapter))
                        }
                    }
                }
            }
        }.listStyle(.plain)
        .navigationTitle(selecting ? "\(selected.count) selected" : "Updates")
        .searchable(text: $search, prompt: "Search updates")
        .refreshable { await model.refreshLibrary() }
        .onChange(of: items.map(\.id)) { _, ids in selected.formIntersection(ids) }
        .confirmationDialog("Delete \(chosen.filter { model.isChapterDownloaded(manga: $0.manga, chapter: $0.chapter) }.count) downloaded chapters?", isPresented: $deleteConfirmation) {
            Button("Delete downloads", role: .destructive) { for item in chosen { model.removeDownloaded(manga: item.manga, chapter: item.chapter) } }
        }
        .sheet(isPresented: $showFilters) {
            NavigationStack {
                Form {
                    Section("Chapter filters") {
                        CollectionFilterPicker(title: "Read", value: $read)
                        CollectionFilterPicker(title: "Downloaded", value: $downloaded)
                        CollectionFilterPicker(title: "Bookmarked", value: $bookmark)
                    }
                    Section {
                        Text("Filters apply to the Updates list and its selection actions. Include keeps matching chapters; Exclude hides them. Downloaded checks files available offline.").font(.footnote).foregroundStyle(.secondary)
                        LabeledContent("Matching chapters", value: "\(items.count)")
                        Button("Reset filters") { read = .any; downloaded = .any; bookmark = .any }
                    }
                }.navigationTitle("Update Filters").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showFilters = false } } }
            }.presentationDetents([.medium, .large])
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Menu {
                Button("Filters", systemImage: "line.3.horizontal.decrease.circle") { showFilters = true }
                Button(selecting ? "Cancel selection" : "Select chapters") { selecting.toggle(); selected.removeAll() }
                Button("Mark displayed updates seen") { model.markUpdatesSeen(items) }
                Button("Mark all updates seen") { model.markAllUpdatesSeen() }
                NavigationLink("Download Queue") { DownloadQueueView() }
            } label: { Image(systemName: "slider.horizontal.3") } }
            if selecting { ToolbarItem(placement: .bottomBar) { Menu("Selection actions") {
                Button("Select all") { selected = Set(items.map(\.id)) }
                Button("Invert selection") { selected = Set(items.map(\.id)).subtracting(selected) }
                Button("Mark read") { mutate(read: true) }.disabled(selected.isEmpty || editsLocked)
                Button("Mark unread") { mutate(read: false) }.disabled(selected.isEmpty || editsLocked)
                Button("Bookmark") { mutate(bookmark: true) }.disabled(selected.isEmpty || editsLocked)
                Button("Remove bookmarks") { mutate(bookmark: false) }.disabled(selected.isEmpty || editsLocked)
                Button("Download") { for item in chosen { model.enqueueDownload(manga: item.manga, chapter: item.chapter) } }.disabled(selected.isEmpty || chosen.allSatisfy { $0.manga.sourceID == "local-files" || model.isChapterDownloaded(manga: $0.manga, chapter: $0.chapter) })
                Button("Delete downloads", role: .destructive) { deleteConfirmation = true }.disabled(chosen.allSatisfy { !model.isChapterDownloaded(manga: $0.manga, chapter: $0.chapter) })
            } } }
        }
    }
    private var editsLocked: Bool { model.state.securityPreferences.lockLibraryEdits }
    private var days: [Date] { Array(Set(items.map { Calendar.current.startOfDay(for: $0.chapter.releaseDate) })).sorted(by: >) }
    private func toggle(_ id: String) { if !selected.insert(id).inserted { selected.remove(id) } }
    private func mutate(read: Bool? = nil, bookmark: Bool? = nil) {
        for item in chosen {
            if let read { model.setChaptersRead([item.chapter.id], mangaID: item.manga.id, read: read) }
            if let bookmark { model.setChaptersBookmarked([item.chapter.id], mangaID: item.manga.id, bookmarked: bookmark) }
        }
    }
    private func identity(_ item: UpdateFeedItem) -> some View {
        let state = model.chapterState(for: item.chapter.id, mangaID: item.manga.id)
        return VStack(alignment: .leading, spacing: 3) {
            Text(item.manga.title).font(.subheadline.weight(.medium))
            Text(item.chapter.title).font(.caption).foregroundStyle(.secondary)
            HStack {
                if state.isRead { Label("Read", systemImage: "checkmark") }
                if state.isBookmarked { Image(systemName: "bookmark.fill").accessibilityLabel("Bookmarked") }
                if model.isChapterDownloaded(manga: item.manga, chapter: item.chapter) { Image(systemName: "arrow.down.circle.fill").accessibilityLabel("Downloaded") }
                if !model.isUpdateSeen(item) { Text("New") }
                if !model.canReadChapter(item.chapter, manga: item.manga) { Text("Source unavailable") }
            }.font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
