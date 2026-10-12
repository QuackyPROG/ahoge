// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

struct MangaDetailView: View {
    @EnvironmentObject private var model: AppModel

    let manga: Manga

    @State private var sortDescending = true
    @State private var showCover = false
    @State private var displayManga: Manga
    @State private var loadedChapters: [Chapter]
    @State private var isLoading = false
    @State private var showDownloadAllConfirm = false
    @State private var showRemoveAllDownloadsConfirm = false
    @State private var summaryExpanded = false

    init(manga: Manga) {
        self.manga = manga
        _displayManga = State(initialValue: manga)
        _loadedChapters = State(initialValue: [])
    }

    private var sortedChapters: [Chapter] {
        let items = loadedChapters.isEmpty ? model.chapters(for: displayManga) : loadedChapters
        return sortDescending ? items : Array(items.reversed())
    }

    private var startChapter: Chapter? {
        model.startChapter(for: displayManga) ?? sortedChapters.first
    }

    var body: some View {
        let hideSensitiveCovers = model.state.securityPreferences.hideSensitiveCovers
        let allowsAdultContent = model.source(for: displayManga.sourceID)?.allowsAdultContent ?? false

        ScrollView {
            LazyVStack(alignment: .leading, spacing: AhogeLayout.sectionSpacing) {
                hero(
                    hideSensitiveCovers: hideSensitiveCovers,
                    allowsAdultContent: allowsAdultContent
                )

                if let startChapter {
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
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(bindings) { binding in
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(binding.service.rawValue)
                                            .font(.subheadline.weight(.semibold))
                                        Text(binding.status)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("\(binding.progressText) · Score \(binding.score)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(12)
                                    .frame(minWidth: 160, alignment: .leading)
                                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        }
        .navigationTitle(displayManga.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showCover) {
            CoverSheet(
                manga: displayManga,
                hideSensitiveCover: hideSensitiveCovers,
                allowsAdultContent: allowsAdultContent
            )
        }
        .confirmationDialog("Download all chapters?", isPresented: $showDownloadAllConfirm) {
            Button("Download all") {
                model.enqueueDownloadAllChapters(manga: displayManga, chapters: sortedChapters)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will enqueue up to \(sortedChapters.count) chapter downloads.")
        }
        .confirmationDialog("Remove all downloads?", isPresented: $showRemoveAllDownloadsConfirm) {
            Button("Remove all", role: .destructive) {
                model.removeAllDownloads(manga: displayManga)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete offline files for \(sortedChapters.count) chapters.")
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
        HStack(alignment: .top, spacing: 18) {
            MangaCoverView(
                manga: displayManga,
                hideSensitiveCover: hideSensitiveCovers,
                allowsAdultContent: allowsAdultContent,
                cornerRadius: 20
            )
            .frame(width: 132, height: 188)
            .shadow(color: .black.opacity(0.16), radius: 14, y: 7)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onTapGesture { showCover = true }
            .accessibilityLabel("Open cover for \(displayManga.title)")

            VStack(alignment: .leading, spacing: 9) {
                Text(displayManga.title)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)

                if !displayManga.author.isEmpty {
                    Text(displayManga.author)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
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
                        .lineLimit(3)
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
        HStack(spacing: 10) {
            detailAction(
                title: model.isInLibrary(displayManga) ? "In Library" : "Library",
                systemImage: model.isInLibrary(displayManga) ? "bookmark.fill" : "bookmark"
            ) {
                model.toggleLibrary(displayManga)
            }

            if displayManga.sourceID != "local-files", !sortedChapters.isEmpty {
                detailAction(title: "Download", systemImage: "arrow.down.circle") {
                    if sortedChapters.count > 20 { showDownloadAllConfirm = true }
                    else { model.enqueueDownloadAllChapters(manga: displayManga, chapters: sortedChapters) }
                }
            }

            NavigationLink {
                MangaTrackingView(manga: displayManga)
            } label: {
                actionRailLabel(title: "Track", systemImage: "person.badge.clock")
            }
            .buttonStyle(.plain)

            Menu {
                NavigationLink {
                    MangaNotesView(manga: displayManga)
                } label: {
                    Label("Notes", systemImage: "note.text")
                }

                if model.isInLibrary(displayManga), !model.categories.isEmpty {
                    Menu("Category", systemImage: "folder") {
                        ForEach(model.categories) { category in
                            Button(category.name, systemImage: category.systemImage) {
                                model.assignCategory(category.id, to: displayManga)
                            }
                        }
                    }
                }

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
                        if sortedChapters.count > 20 { showRemoveAllDownloadsConfirm = true }
                        else { model.removeAllDownloads(manga: displayManga) }
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
        .buttonStyle(.plain)
    }

    private func actionRailLabel(title: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.headline)
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    withAnimation(.easeInOut(duration: 0.18)) { summaryExpanded.toggle() }
                }
                .font(.subheadline.weight(.semibold))
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
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var chaptersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AhogeSectionHeader("Chapters", subtitle: sortedChapters.isEmpty ? nil : "\(sortedChapters.count) available") {
                Button {
                    withAnimation(.snappy) { sortDescending.toggle() }
                } label: {
                    Label(sortDescending ? "Newest" : "Oldest", systemImage: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.semibold))
                }
            }

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
                    ForEach(Array(sortedChapters.enumerated()), id: \.offset) { index, chapter in
                        chapterLink(chapter)
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
            ReaderView(manga: displayManga, initialChapter: chapter)
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
                    if chapter.isDownloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Downloaded")
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }

                if isCurrent, let progressText = model.progressDisplayText(for: displayManga, fallbackChapter: chapter) {
                    Text(progressText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !chapter.isDownloaded, let job = model.downloadJob(for: displayManga, chapter: chapter) {
                    ChapterDownloadInlineStatusView(job: job)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            chapterContextMenu(chapter)
        }
    }

    @ViewBuilder
    private func chapterContextMenu(_ chapter: Chapter) -> some View {
        if displayManga.sourceID != "local-files" {
            if chapter.isDownloaded {
                Button(role: .destructive) {
                    model.removeDownloaded(manga: displayManga, chapter: chapter)
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
                        model.removeDownloaded(manga: displayManga, chapter: chapter)
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
                Text("\(completed)/\(total)").font(.caption2).foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
            if failed > 0 {
                Text("\(failed) failed")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                Text("Queued").font(.caption2).foregroundStyle(.secondary)
            case .downloading:
                ProgressView(value: min(max(job.progress, 0), 1)).frame(maxWidth: 150)
                Text("\(Int(job.progress * 100))%").font(.caption2).foregroundStyle(.secondary)
            case .paused:
                Label("Paused", systemImage: "pause.circle").font(.caption2).foregroundStyle(.secondary)
            case .failed:
                Label("Failed", systemImage: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.red)
                Button("Retry") { model.retryDownload(jobID: job.id) }
                    .font(.caption2.weight(.semibold))
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
            VStack(spacing: 20) {
                MangaCoverView(
                    manga: manga,
                    hideSensitiveCover: hideSensitiveCover,
                    allowsAdultContent: allowsAdultContent,
                    cornerRadius: 26
                )
                .frame(maxHeight: 430)
                .padding(.top, 20)

                ShareLink(item: manga.title) {
                    Label("Share Title", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding(.horizontal, 24)
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
            TextEditor(text: $note)
                .frame(minHeight: 220)

            Button("Save Note") {
                model.saveNote(note, for: manga)
            }
        }
        .navigationTitle("Notes")
        .onAppear { note = model.note(for: manga) }
    }
}
