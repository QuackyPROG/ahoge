// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

struct MangaDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let manga: Manga

    @State private var sortDescending = true
    @State private var showCover = false
    @State private var displayManga: Manga
    @State private var loadedChapters: [Chapter]
    @State private var isLoading = false
    @State private var showDownloadAllConfirm = false
    @State private var showRemoveAllDownloadsConfirm = false
    @State private var summaryExpanded = false
    @State private var chapterSearch = ""
    @State private var readFilter: CollectionFilter = .any
    @State private var downloadedFilter: CollectionFilter = .any
    @State private var bookmarkFilter: CollectionFilter = .any
    @State private var selecting = false
    @State private var selected = Set<String>()
    @State private var showCategories = false
    @State private var deleteSelected = false

    init(manga: Manga) {
        self.manga = manga
        _displayManga = State(initialValue: manga)
        _loadedChapters = State(initialValue: [])
    }

    private var sortedChapters: [Chapter] {
        let items = loadedChapters.isEmpty ? model.chapters(for: displayManga) : loadedChapters
        let filtered = items.filter { chapter in
            let state = model.chapterState(for: chapter.id, mangaID: displayManga.id)
            return (chapterSearch.isEmpty || chapter.title.localizedCaseInsensitiveContains(chapterSearch)) && readFilter.matches(state.isRead) && bookmarkFilter.matches(state.isBookmarked) && downloadedFilter.matches(model.isChapterDownloaded(manga: displayManga, chapter: chapter))
        }
        return sortDescending ? filtered : Array(filtered.reversed())
    }

    private var startChapter: Chapter? {
        model.startChapter(for: displayManga) ?? sortedChapters.first
    }

    var body: some View {
        let hideSensitiveCovers = model.state.securityPreferences.hideSensitiveCovers
        let allowsAdultContent = model.source(for: displayManga.sourceID)?.allowsAdultContent ?? false

        ScrollView {
            LazyVStack(alignment: .leading, spacing: AhogeLayout.sectionSpacing) {
                VStack(alignment: .leading, spacing: 16) {
                    hero(
                        hideSensitiveCovers: hideSensitiveCovers,
                        allowsAdultContent: allowsAdultContent
                    )

                    if let startChapter, model.canReadChapter(startChapter, manga: displayManga) {
                        NavigationLink {
                            ReaderView(manga: displayManga, initialChapter: startChapter)
                        } label: {
                            Label(model.progress(for: displayManga) == nil ? "Start Reading" : "Resume Reading", systemImage: "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 15))
                    }

                    actionRail
                }

                if !displayManga.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    descriptionSection
                }

                if let error = model.sourceError(for: displayManga.sourceID) {
                    sourceErrorCard(error)
                } else if model.resolvedSourceOrNil(for: displayManga.sourceID) == nil {
                    sourceErrorCard("This title's source is unavailable. Cached metadata and downloaded content remain accessible.")
                }

                let bindings = model.trackerBindings(for: displayManga)
                if !bindings.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        AhogeSectionHeader("Tracking") {
                            NavigationLink("Manage") { MangaTrackingView(manga: displayManga) }
                                .font(.subheadline.weight(.semibold))
                                .frame(minHeight: 44)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(bindings) { binding in
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("Local record · \(binding.service.rawValue)")
                                            .font(.subheadline.weight(.semibold))
                                        Text(binding.status)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("\(binding.progressText) · Score \(binding.score)")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Divider()
                                }
                            }
                        }
                    }
                }

                chaptersSection
            }
            .padding(.horizontal, AhogeLayout.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(displayManga.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showCategories) { CollectionCategoryPicker(mangaIDs: [displayManga.id]) }
        .onChange(of: sortedChapters.map(\.id)) { _, ids in selected.formIntersection(ids) }
        .confirmationDialog("Delete \(selectedDownloads.count) downloaded chapters?", isPresented: $deleteSelected) {
            Button("Delete downloads", role: .destructive) { for chapter in selectedDownloads { model.removeDownloaded(manga: displayManga, chapter: chapter) } }
        }
        .refreshable { displayManga = await model.refreshMangaDetails(for: displayManga); loadedChapters = await model.refreshChapters(for: displayManga) }
        .sheet(isPresented: $showCover) {
            CoverSheet(
                manga: displayManga,
                hideSensitiveCover: hideSensitiveCovers,
                allowsAdultContent: allowsAdultContent
            )
        }
        .confirmationDialog("Download displayed chapters?", isPresented: $showDownloadAllConfirm) {
            Button("Download displayed chapters") {
                model.enqueueDownloadAllChapters(manga: displayManga, chapters: sortedChapters)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will enqueue up to \(sortedChapters.filter { !model.isChapterDownloaded(manga: displayManga, chapter: $0) }.count) chapter downloads, using the current filters.")
        }
        .confirmationDialog("Remove all downloads?", isPresented: $showRemoveAllDownloadsConfirm) {
            Button("Remove all", role: .destructive) {
                model.removeAllDownloads(manga: displayManga)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete offline files for \(model.chapters(for: displayManga).filter { model.isChapterDownloaded(manga: displayManga, chapter: $0) }.count) chapters.")
        }
        .onChange(of: model.chapterCache[displayManga.id]) { _, newValue in
            if let newValue, !newValue.isEmpty { loadedChapters = newValue }
        }
        .task {
            guard model.supportsLiveSource(sourceID: displayManga.sourceID) else {
                loadedChapters = model.chapters(for: displayManga)
                return
            }
            isLoading = true
            displayManga = await model.refreshMangaDetails(for: displayManga)
            loadedChapters = await model.refreshChapters(for: displayManga)
            isLoading = false
        }
    }

    private func hero(hideSensitiveCovers: Bool, allowsAdultContent: Bool) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 20))
        return layout {
            Button { showCover = true } label: {
                MangaCoverView(
                    manga: displayManga,
                    hideSensitiveCover: hideSensitiveCovers,
                    allowsAdultContent: allowsAdultContent,
                    cornerRadius: 12
                )
                .frame(width: 140, height: 200)

            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open cover for \(displayManga.title)")

            VStack(alignment: .leading, spacing: 9) {
                Text(displayManga.title)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                if !displayManga.author.isEmpty {
                    Text(displayManga.author)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    AhogeStatusBadge(title: displayManga.statusText, systemImage: "circle.fill")
                    if let source = model.source(for: displayManga.sourceID) {
                        AhogeStatusBadge(title: source.name, systemImage: source.systemImage)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                if !displayManga.genres.isEmpty {
                    Text(displayManga.genres.prefix(4).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isLoading {
                    Label("Refreshing…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var actionRail: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            detailAction(
                title: model.isInLibrary(displayManga) ? "In Library" : "Library",
                systemImage: model.isInLibrary(displayManga) ? "bookmark.fill" : "bookmark"
            ) {
                model.toggleLibrary(displayManga)
            }.disabled(model.state.securityPreferences.lockLibraryEdits)

            if displayManga.sourceID != "local-files", !sortedChapters.isEmpty {
                detailAction(title: "Download", systemImage: "arrow.down.circle") {
                    showDownloadAllConfirm = true
                }
            }

            Menu {
                NavigationLink { MangaTrackingView(manga: displayManga) } label: {
                    Label("Track", systemImage: "person.badge.clock")
                }
                NavigationLink {
                    MangaNotesView(manga: displayManga)
                } label: {
                    Label("Notes", systemImage: "note.text")
                }

                if model.isInLibrary(displayManga) {
                    Button("Categories", systemImage: "folder") { showCategories = true }.disabled(model.state.securityPreferences.lockLibraryEdits)
                }
                ShareLink(item: displayManga.title) { Label("Share title", systemImage: "square.and.arrow.up") }

                if let migrationSource = model.migrationSource(for: displayManga) {
                    NavigationLink {
                        MigrationConfirmationView(source: migrationSource, target: displayManga)
                    } label: {
                        Label("Migrate Title", systemImage: "arrow.triangle.swap")
                    }
                }

                if let source = model.resolvedSourceOrNil(for: displayManga.sourceID),
                   let webURL = model.sourceWebURL(for: source, manga: displayManga) {
                    Link(destination: webURL) {
                        Label("Open in Web", systemImage: "safari")
                    }
                }

                if displayManga.sourceID != "local-files" && model.isTitleDownloaded(manga: displayManga) {
                    Button(role: .destructive) {
                        showRemoveAllDownloadsConfirm = true
                    } label: {
                        Label("Remove Downloads", systemImage: "trash")
                    }
                }
            } label: {
                actionRailLabel(title: "More", systemImage: "ellipsis")
            }
        }

        let titleJobs = model.downloadJobs.filter { $0.mangaID == displayManga.id && $0.sourceID == displayManga.sourceID }
        if !titleJobs.isEmpty {
            MangaDownloadAggregateView(jobs: titleJobs)
                .padding(.top, 2)
        }
    }

    private func detailAction(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionRailLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
    }

    private func actionRailLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AhogeSectionHeader("About")
            Text(displayManga.summary)
                .font(.body)
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .lineLimit(summaryExpanded ? nil : 5)

            if displayManga.summary.count > 240 {
                Button(summaryExpanded ? "Show Less" : "Read More") {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { summaryExpanded.toggle() }
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
            }
        }
    }

    private func sourceErrorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Source unavailable")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AhogePalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var chaptersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AhogeSectionHeader("Chapters", subtitle: sortedChapters.isEmpty ? nil : "\(sortedChapters.count) available") {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy) { sortDescending.toggle() }
                } label: {
                    Label(sortDescending ? "Newest" : "Oldest", systemImage: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
            }

            TextField("Search chapters", text: $chapterSearch).textFieldStyle(.roundedBorder).accessibilityLabel("Search chapters")
            HStack {
                Menu("Filter", systemImage: "line.3.horizontal.decrease.circle") {
                    CollectionFilterPicker(title: "Read", value: $readFilter)
                    CollectionFilterPicker(title: "Downloaded", value: $downloadedFilter)
                    CollectionFilterPicker(title: "Bookmarked", value: $bookmarkFilter)
                }
                Spacer()
                Button(selecting ? "Done" : "Select") { selecting.toggle(); selected.removeAll() }
                if selecting {
                    Menu("\(selected.count) selected") {
                        Button("Select all") { selected = Set(sortedChapters.map(\.id)) }
                        Button("Invert selection") { selected = Set(sortedChapters.map(\.id)).subtracting(selected) }
                        Button("Mark read") { model.setChaptersRead(Array(selected), mangaID: displayManga.id, read: true) }.disabled(selected.isEmpty || model.state.securityPreferences.lockLibraryEdits)
                        Button("Mark unread") { model.setChaptersRead(Array(selected), mangaID: displayManga.id, read: false) }.disabled(selected.isEmpty || model.state.securityPreferences.lockLibraryEdits)
                        Button("Bookmark") { model.setChaptersBookmarked(Array(selected), mangaID: displayManga.id, bookmarked: true) }.disabled(selected.isEmpty || model.state.securityPreferences.lockLibraryEdits)
                        Button("Remove bookmarks") { model.setChaptersBookmarked(Array(selected), mangaID: displayManga.id, bookmarked: false) }.disabled(selected.isEmpty || model.state.securityPreferences.lockLibraryEdits)
                        Button("Download") { model.enqueueDownloadAllChapters(manga: displayManga, chapters: sortedChapters.filter { selected.contains($0.id) }) }.disabled(selected.isEmpty || displayManga.sourceID == "local-files")
                        Button("Delete downloads", role: .destructive) { deleteSelected = true }.disabled(selectedDownloads.isEmpty)
                    }
                }
            }.font(.subheadline)

            if isLoading && sortedChapters.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading chapters…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 90)
            } else if sortedChapters.isEmpty {
                ContentUnavailableView(
                    "No chapters available",
                    systemImage: "text.page.slash",
                    description: Text("Try refreshing the source later.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sortedChapters.enumerated()), id: \.element.id) { index, chapter in
                        if selecting {
                            Button { if !selected.insert(chapter.id).inserted { selected.remove(chapter.id) } } label: {
                                HStack { Image(systemName: selected.contains(chapter.id) ? "checkmark.circle.fill" : "circle"); Text(chapter.title); Spacer() }.frame(minHeight: 44)
                            }.buttonStyle(.plain)
                        } else { chapterLink(chapter) }
                        if index < sortedChapters.count - 1 {
                            Divider().padding(.leading, 4)
                        }
                    }
                }
            }
        }
    }

    private func chapterLink(_ chapter: Chapter) -> some View {
        let progress = model.progress(for: displayManga)
        let isCurrent = progress?.chapterID == chapter.id

        return NavigationLink {
            if model.canReadChapter(chapter, manga: displayManga) { ReaderView(manga: displayManga, initialChapter: chapter) }
            else { ContentUnavailableView("Chapter unavailable", systemImage: "wifi.exclamationmark", description: Text("Restore its source or download this chapter when the source is available.")) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chapter.title)
                            .font(.body.weight(isCurrent ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Text(chapter.releaseDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isCurrent {
                        Image(systemName: "book.fill")
                            .foregroundStyle(.tint)
                            .accessibilityLabel("Current chapter")
                    }
                    if model.chapterState(for: chapter.id, mangaID: displayManga.id).isRead { Image(systemName: "checkmark").accessibilityLabel("Read") }
                    if model.chapterState(for: chapter.id, mangaID: displayManga.id).isBookmarked { Image(systemName: "bookmark.fill").accessibilityLabel("Bookmarked") }
                    if model.isChapterDownloaded(manga: displayManga, chapter: chapter) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Downloaded")
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }

                if isCurrent, let progressText = model.progressDisplayText(for: displayManga, fallbackChapter: chapter) {
                    Text(progressText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !model.isChapterDownloaded(manga: displayManga, chapter: chapter), let job = model.downloadJob(for: displayManga, chapter: chapter) {
                    ChapterDownloadInlineStatusView(job: job)
                }
            }
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .contextMenu {
            chapterContextMenu(chapter)
        }
    }

    private var selectedDownloads: [Chapter] { model.chapters(for: displayManga).filter { selected.contains($0.id) && model.isChapterDownloaded(manga: displayManga, chapter: $0) } }

    @ViewBuilder
    private func chapterContextMenu(_ chapter: Chapter) -> some View {
        Button("Select") { selecting = true; selected.insert(chapter.id) }
        Button(model.chapterState(for: chapter.id, mangaID: displayManga.id).isRead ? "Mark unread" : "Mark read") { model.setChaptersRead([chapter.id], mangaID: displayManga.id, read: !model.chapterState(for: chapter.id, mangaID: displayManga.id).isRead) }
        Button(model.chapterState(for: chapter.id, mangaID: displayManga.id).isBookmarked ? "Remove bookmark" : "Bookmark") { model.setChaptersBookmarked([chapter.id], mangaID: displayManga.id, bookmarked: !model.chapterState(for: chapter.id, mangaID: displayManga.id).isBookmarked) }
        if displayManga.sourceID != "local-files" {
            if model.isChapterDownloaded(manga: displayManga, chapter: chapter) {
                Button(role: .destructive) {
                    selected = [chapter.id]; deleteSelected = true
                } label: {
                    Label("Remove download", systemImage: "trash")
                }
            } else if let job = model.downloadJob(for: displayManga, chapter: chapter) {
                switch job.state {
                case .queued, .downloading, .paused:
                    Button(role: .destructive) {
                        model.cancelDownload(jobID: job.id)
                    } label: {
                        Label("Cancel download", systemImage: "xmark.circle")
                    }
                case .failed:
                    Button {
                        model.retryDownload(jobID: job.id)
                    } label: {
                        Label("Retry download", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        model.cancelDownload(jobID: job.id)
                    } label: {
                        Label("Cancel download", systemImage: "xmark.circle")
                    }
                case .complete:
                    Button(role: .destructive) {
                        selected = [chapter.id]; deleteSelected = true
                    } label: {
                        Label("Remove download", systemImage: "trash")
                    }
                }
            } else {
                Button {
                    model.enqueueDownload(manga: displayManga, chapter: chapter)
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }
        }
    }
}

private struct MangaDownloadAggregateView: View {
    let jobs: [DownloadJob]

    private var total: Int { jobs.count }
    private var completed: Int { jobs.filter { $0.state == .complete }.count }
    private var failed: Int { jobs.filter { $0.state == .failed }.count }

    private var progress: Double {
        guard total > 0 else { return 0 }
        let sum = jobs.reduce(0.0) { partial, job in
            switch job.state {
            case .complete: return partial + 1
            case .downloading: return partial + min(max(job.progress, 0), 1)
            case .queued, .paused, .failed: return partial
            }
        }
        return min(max(sum / Double(total), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Downloads").font(.caption.weight(.semibold))
                Spacer()
                Text("\(completed)/\(total)").font(.footnote).monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .accessibilityLabel("Chapter downloads")
                .accessibilityValue("\(completed) of \(total) complete")
            if failed > 0 {
                Text("\(failed) failed")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(AhogePalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ChapterDownloadInlineStatusView: View {
    @EnvironmentObject private var model: AppModel
    let job: DownloadJob

    var body: some View {
        HStack(spacing: 8) {
            switch job.state {
            case .queued:
                ProgressView().controlSize(.small)
                Text("Queued").font(.footnote).foregroundStyle(.secondary)
            case .downloading:
                ProgressView(value: min(max(job.progress, 0), 1)).frame(maxWidth: 150)
                Text("\(Int(job.progress * 100))%").font(.footnote).foregroundStyle(.secondary)
            case .paused:
                Label("Paused", systemImage: "pause.circle").font(.footnote).foregroundStyle(.secondary)
            case .failed:
                Label("Failed", systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red)
                Button("Retry") { model.retryDownload(jobID: job.id) }
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: 44)
                    .buttonStyle(.borderless)
            case .complete:
                EmptyView()
            }
            Spacer(minLength: 0)
        }
    }
}

private struct CoverSheet: View {
    @Environment(\.dismiss) private var dismiss
    let manga: Manga
    let hideSensitiveCover: Bool
    let allowsAdultContent: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: 20) {
                Text(manga.title).font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                MangaCoverView(
                    manga: manga,
                    hideSensitiveCover: hideSensitiveCover,
                    allowsAdultContent: allowsAdultContent,
                    cornerRadius: 12
                )
                .aspectRatio(0.70, contentMode: .fit)
                .frame(maxWidth: 320)
                .padding(.top, 20)

                ShareLink(item: manga.title) {
                    Label("Share Title", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            }
            .navigationTitle("Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

struct MangaNotesView: View {
    @EnvironmentObject private var model: AppModel
    let manga: Manga
    @State private var note = ""

    var body: some View {
        Form {
            Section {
                Text(manga.title).font(.headline)
                TextEditor(text: $note)
                    .frame(minHeight: 220)
                    .accessibilityLabel("Notes for \(manga.title)")
                    .disabled(model.state.securityPreferences.lockLibraryEdits)
            } header: { Text("Reading notes") }
            Section {
                Button("Save Note") {
                    model.saveNote(note, for: manga)
                }.disabled(model.state.securityPreferences.lockLibraryEdits)
                .frame(minHeight: 44)
            }
        }
        .navigationTitle("Notes")
        .onAppear { note = model.note(for: manga) }
    }
}
