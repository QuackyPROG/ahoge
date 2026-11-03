import PhotosUI
import SwiftUI

struct MangaDetailView: View {
    let ref: MangaRef
    @EnvironmentObject private var sources: SourceManager
    @EnvironmentObject private var repo: LibraryRepository
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.palette) private var palette
    @State private var isLoading = false
    @State private var error: Error?
    @State private var expanded = false
    @State private var reading: ChapterRecord?
    @State private var webTarget: WebTarget?
    @State private var showCover = false
    @AppStorage(Pref.libraryDefaultCategory.name) private var defaultCategory = LibraryPrefs.alwaysAsk
    @State private var choosingCategories = false
    @State private var display: ChapterDisplay
    @State private var selecting = false
    @State private var selection = Set<String>()
    @State private var visible = VisibleRows()
    @State private var removedWithDownloads: LibraryManga?
    /// Scanlators hidden for this manga, loaded from the repository.
    @State private var excluded = Set<String>()
    @State private var filteringScanlators = false
    @State private var editingNotes = false
    @State private var choosingDefault = false
    /// A genre long-pressed for a search across sources.
    @State private var globalQuery: String?
    /// This entry, pushed as the migration search.
    @State private var migrating: MangaRef?
    @AppStorage(Pref.hideMissingChapters.name) private var hideMissing = false

    init(ref: MangaRef) {
        self.ref = ref
        let key = LibraryManga.makeKey(sourceId: ref.sourceId, url: ref.url)
        _display = State(initialValue: ChapterDisplay.load(for: key))
    }

    private var manga: LibraryManga? { repo.manga(sourceId: ref.sourceId, url: ref.url) }
    private var info: InstalledSource? { sources.installed(ref.sourceId) }
    private var headers: [String: String] { info.map { ["Referer": $0.baseUrl + "/"] } ?? [:] }
    private var cover: String { manga?.displayCover.nonEmpty ?? ref.cover }
    private var webURL: String? {
        guard let info else { return nil }
        if let manga { return manga.webURL(baseUrl: info.baseUrl) }
        return LibraryManga(sourceId: ref.sourceId, url: ref.url, title: ref.title, coverUrl: "").webURL(baseUrl: info.baseUrl)
    }

    var body: some View {
        let chapters = manga.map { display.apply(to: $0.chapters, excluding: excluded) } ?? []
        ScrollViewReader { proxy in
            List(selection: $selection) {
                Section {
                    header.listRowInsets(EdgeInsets()).listRowBackground(backdrop)
                }
                .listRowSeparator(.hidden)
                if let error, manga?.chapters.isEmpty ?? true {
                    Section {
                        ErrorStateView(error: error, retry: { Task { await refresh() } }, openWeb: { webTarget = WebTarget(url: $0) })
                    }
                    .listRowSeparator(.hidden)
                    .themedRows(plain: true)
                }
                if let manga {
                    Section {
                        ForEach(Array(chapters.enumerated()), id: \.element.key) { index, chapter in
                            chapterRow(chapter, in: manga)
                                .id(chapter.key)
                                .tag(chapter.key)
                                .onAppear { visible.appeared(index) }
                                .onDisappear { visible.disappeared(index) }
                            if let gap = missing(after: index, in: chapters) { missingRow(gap) }
                        }
                    } header: {
                        chapterHeader(manga, shown: chapters.count)
                    }
                    .themedRows(plain: true)
                }
            }
            .listStyle(.plain)
            .themedScreen()
            .scrollIndicators(chapters.count > 40 ? .hidden : .automatic)
            .environment(\.editMode, .constant(selecting ? .active : .inactive))
            .overlay(alignment: .trailing) {
                if chapters.count > 40 {
                    FastScroller(
                        count: chapters.count,
                        rows: visible,
                        label: { chapters[$0].number >= 0 ? "Ch. \(chapters[$0].number.formatted())" : chapters[$0].name },
                        scrollTo: { proxy.scrollTo(chapters[$0].key, anchor: .top) }
                    )
                    .padding(.top, 280)
                    .padding(.bottom, 90)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) { if !selecting { resumeButton } }
        .safeAreaInset(edge: .bottom) { if selecting, let manga { selectionBar(manga) } }
        .navigationTitle(selecting ? "\(selection.count) selected" : "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(selecting)
        .refreshable { await refresh() }
        .task {
            repo.upsert(sourceId: ref.sourceId, url: ref.url, title: ref.title, cover: ref.cover)
            excluded = repo.excludedScanlators(mangaKey: LibraryManga.makeKey(sourceId: ref.sourceId, url: ref.url))
            if manga?.lastChapterFetch == nil { await refresh() }
        }
        .onChange(of: display) { _, value in value.save(for: LibraryManga.makeKey(sourceId: ref.sourceId, url: ref.url)) }
        .toolbar { toolbarItems(chapters) }
        .sheet(item: $webTarget) { WebViewSheet(target: $0) }
        .sheet(isPresented: $showCover) { CoverSheet(url: cover, headers: headers, manga: manga) }
        .sheet(isPresented: $filteringScanlators) {
            if let manga {
                ScanlatorFilterSheet(scanlators: Set(manga.chapters.compactMap(\.scanlator).filter { !$0.isEmpty }).sorted(), excluded: excluded) {
                    excluded = $0
                    repo.setExcludedScanlators($0, for: manga)
                }
            }
        }
        .sheet(isPresented: $editingNotes) {
            if let manga { NotesSheet(notes: manga.notes) { repo.setNotes($0, for: manga) } }
        }
        .navigationDestination(item: $globalQuery) { RouteView(route: .globalSearch($0)) }
        .navigationDestination(item: $migrating) { RouteView(route: .migrate($0)) }
        .confirmationDialog("Use these chapter settings as the default?", isPresented: $choosingDefault, titleVisibility: .visible) {
            Button("For new entries") { display.saveAsDefault() }
            Button("For all entries in my library") {
                display.saveAsDefault(clearing: repo.library.map(\.key))
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $choosingCategories) {
            if let manga { SetCategoriesSheet(manga: [manga]) }
        }
        .alert("Delete downloaded chapters?", isPresented: Binding(get: { removedWithDownloads != nil }, set: { if !$0 { removedWithDownloads = nil } })) {
            Button("Delete", role: .destructive) {
                if let manga = removedWithDownloads { downloads.delete(manga.chapters) }
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("The title is no longer in your library.")
        }
        .fullScreenCover(item: $reading) { chapter in
            if let manga { ReaderView(sourceId: ref.sourceId, manga: manga, chapter: chapter) }
        }
    }

    // MARK: Header

    private var backdrop: some View {
        GeometryReader { geometry in
            RemoteImage(url: cover, headers: headers, maxPixelWidth: MangaCard.coverPixelWidth)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .blur(radius: 18)
                .opacity(0.45)
                .clipped()
                .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
        }
        .background(palette.background.color)
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Button { showCover = true } label: {
                    Color.clear
                        .frame(width: 112, height: 168)
                        .overlay { RemoteImage(url: cover, headers: headers, maxPixelWidth: MangaCard.coverPixelWidth) }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show cover")
                VStack(alignment: .leading, spacing: 5) {
                    Text(manga?.title ?? ref.title)
                        .font(.title3.bold())
                        .lineLimit(4)
                        .contextMenu {
                            Button { UIPasteboard.general.string = manga?.title ?? ref.title } label: { Label("Copy title", systemImage: "doc.on.doc") }
                        }
                    if let author = manga?.author.nonEmpty { searchLink(author, icon: "person") }
                    if let artist = manga?.artist.nonEmpty, artist != manga?.author { searchLink(artist, icon: "paintbrush") }
                    HStack(spacing: 6) {
                        if let status = manga?.status { Label(Self.statusTitle(status), systemImage: Self.statusIcon(status)) }
                        Text("•")
                        Text(info?.name ?? ref.sourceId)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .labelStyle(CompactLabelStyle())
                .padding(.top, 4)
            }
            actions
            if let summary = manga?.summary.nonEmpty { MangaDescription(summary: summary, expanded: $expanded) }
            if let notes = manga?.notes.nonEmpty { notesBlock(notes) }
            if let genres = manga?.genres, !genres.isEmpty { genreChips(genres) }
            if isLoading && (manga?.chapters.isEmpty ?? true) { ProgressView().frame(maxWidth: .infinity) }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var actions: some View {
        HStack(spacing: 0) {
            let inLibrary = manga?.inLibrary == true
            ActionButton(title: inLibrary ? "In library" : "Add to library", icon: inLibrary ? "heart.fill" : "heart", active: inLibrary) { toggleLibrary() }
            if manga != nil {
                ActionButton(title: "Notes", icon: manga?.notes.isEmpty == false ? "note.text" : "note.text.badge.plus", active: manga?.notes.isEmpty == false) { editingNotes = true }
            }
            if inLibrary, let manga {
                ActionButton(title: "Migrate", icon: "arrow.left.arrow.right") { migrating = manga.ref }
            }
            if let webURL {
                ActionButton(title: "WebView", icon: "globe") { webTarget = WebTarget(url: webURL) }
            }
        }
    }

    /// Tapping an author searches the source for their other work.
    private func searchLink(_ name: String, icon: String) -> some View {
        NavigationLink(value: Route.sourceSearch(ref.sourceId, query: name)) {
            Label(name, systemImage: icon).font(.subheadline)
        }
        .buttonStyle(.plain)
    }

    private func notesBlock(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Notes", systemImage: "note.text").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(DescriptionFormatter.attributed(notes))
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture { editingNotes = true }
    }

    @ViewBuilder
    private func genreChips(_ genres: [String]) -> some View {
        let chips = ForEach(genres, id: \.self) { genre in
            NavigationLink(value: Route.sourceGenre(ref.sourceId, genre: genre)) {
                Text(genre)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .overlay(Capsule().strokeBorder(.secondary.opacity(0.4)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Search all sources", systemImage: "magnifyingglass") { globalQuery = genre }
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = genre }
            }
        }
        if expanded {
            FlowLayout { chips }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { chips }
            }
        }
    }

    // MARK: Chapters

    private func chapterHeader(_ manga: LibraryManga, shown: Int) -> some View {
        let filtered = display != ChapterDisplay.globalDefault() || !excluded.isEmpty
        return HStack {
            let total = manga.chapters.count
            Text(shown == total ? "\(total) chapters" : "\(shown) of \(total) chapters")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Menu {
                Picker("Sort", selection: $display.sort) {
                    ForEach(ChapterDisplay.Sort.allCases) { Text($0.title).tag($0) }
                }
                Picker("Order", selection: $display.ascending) {
                    Text("Newest first").tag(false)
                    Text("Oldest first").tag(true)
                }
                Picker("Show", selection: $display.filter) {
                    ForEach(ChapterDisplay.Filter.allCases) { Text($0.title).tag($0) }
                }
                Picker("Bookmarks", selection: $display.bookmarked) {
                    Text("All chapters").tag(TriState.off)
                    Text("Bookmarked").tag(TriState.include)
                    Text("Not bookmarked").tag(TriState.exclude)
                }
                Picker("Titles", selection: $display.numberTitles) {
                    Text("Source title").tag(false)
                    Text("Chapter number").tag(true)
                }
                if manga.chapters.contains(where: { $0.scanlator?.isEmpty == false }) {
                    Button("Scanlators", systemImage: "person.2") { filteringScanlators = true }
                }
                Button("Set as default", systemImage: "square.and.arrow.down") { choosingDefault = true }
                if filtered {
                    Button("Reset", systemImage: "arrow.counterclockwise") {
                        display = ChapterDisplay.globalDefault()
                        if !excluded.isEmpty {
                            excluded = []
                            repo.setExcludedScanlators([], for: manga)
                        }
                    }
                }
            } label: {
                Image(systemName: filtered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.title3)
            }
            .accessibilityLabel("Sort and filter chapters")
        }
        .textCase(nil)
        .padding(.vertical, 4)
        // Bleeds past the header insets so pinned headers show the theme, not a system band.
        .background { palette.background.color.padding(.horizontal, -40) }
    }

    @ViewBuilder
    private func chapterRow(_ chapter: ChapterRecord, in manga: LibraryManga) -> some View {
        if selecting {
            ChapterRow(chapter: chapter, title: display.title(of: chapter))
        } else {
            HStack(spacing: 4) {
                Button { reading = chapter } label: { ChapterRow(chapter: chapter, title: display.title(of: chapter)) }
                    .buttonStyle(.plain)
                ChapterDownloadButton(chapter: chapter)
            }
            .chapterSwipes(chapter)
            .contextMenu {
                Button("Select", systemImage: "checkmark.circle") { startSelecting(chapter) }
                Button(chapter.read ? "Mark as unread" : "Mark as read", systemImage: chapter.read ? "eye.slash" : "eye") {
                    repo.setRead([chapter], !chapter.read)
                }
                Button(chapter.bookmark ? "Remove bookmark" : "Bookmark", systemImage: chapter.bookmark ? "bookmark.slash" : "bookmark") {
                    repo.setBookmark([chapter], !chapter.bookmark)
                }
                Button("Mark previous as read", systemImage: "arrow.down.to.line") { repo.markPreviousRead(chapter, in: manga) }
                if downloads.isDownloaded(chapter.key) {
                    Button("Delete download", systemImage: "trash", role: .destructive) { downloads.delete([chapter]) }
                } else {
                    Button("Download", systemImage: "arrow.down.circle") { downloads.enqueue([chapter]) }
                }
            }
        }
    }

    /// Chapters missing between a row and the next, from their numbers. Only for the unfiltered list.
    private func missing(after index: Int, in chapters: [ChapterRecord]) -> Int? {
        guard !hideMissing, display.sort != .date, display.filter == .all, display.bookmarked == .off, excluded.isEmpty,
              index + 1 < chapters.count else { return nil }
        let count = ChapterGaps.missing(between: chapters[index].number, and: chapters[index + 1].number)
        return count > 0 ? count : nil
    }

    private func missingRow(_ count: Int) -> some View {
        Label(count == 1 ? "1 missing chapter" : "\(count) missing chapters", systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .selectionDisabled()
            .accessibilityLabel(count == 1 ? "1 chapter missing" : "\(count) chapters missing")
    }

    private func selectionBar(_ manga: LibraryManga) -> some View {
        let chosen = manga.chapters.filter { selection.contains($0.key) }
        return HStack {
            Button("Read", systemImage: "eye") { finishSelection { repo.setRead(chosen, true) } }
            Spacer()
            Button("Unread", systemImage: "eye.slash") { finishSelection { repo.setRead(chosen, false) } }
            Spacer()
            Button(chosen.allSatisfy(\.bookmark) ? "Unmark" : "Bookmark", systemImage: chosen.allSatisfy(\.bookmark) ? "bookmark.slash" : "bookmark") {
                let bookmark = !chosen.allSatisfy(\.bookmark)
                finishSelection { repo.setBookmark(chosen, bookmark) }
            }
            Spacer()
            Button("Previous read", systemImage: "arrow.down.to.line") {
                // The newest selected chapter and everything older.
                finishSelection { if let newest = chosen.min(by: { $0.sourceOrder < $1.sourceOrder }) { repo.markPreviousRead(newest, in: manga) } }
            }
            Spacer()
            Button("Download", systemImage: "arrow.down.circle") {
                // Oldest first, the order they are read in.
                finishSelection { downloads.enqueue(chosen.sorted { $0.sourceOrder > $1.sourceOrder }) }
            }
            Spacer()
            Button("Delete", systemImage: "trash") { finishSelection { downloads.delete(chosen) } }
        }
        .labelStyle(VerticalLabelStyle())
        .disabled(chosen.isEmpty)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private func toolbarItems(_ chapters: [ChapterRecord]) -> some ToolbarContent {
        if selecting {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { finishSelection {} }
            }
            ToolbarItem(placement: .topBarTrailing) {
                let all = Set(chapters.map(\.key))
                Button(selection == all ? "Deselect all" : "Select all") { selection = selection == all ? [] : all }
            }
        } else {
            if let manga, !manga.chapters.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { downloadMenu(manga) }
            }
            if manga?.inLibrary == true {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { choosingCategories = true } label: { Image(systemName: "folder") }
                        .accessibilityLabel("Edit categories")
                }
            }
            if let webURL, let url = URL(string: webURL) {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share")
                }
            }
            if let webURL {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { webTarget = WebTarget(url: webURL) } label: { Image(systemName: "globe") }
                        .accessibilityLabel("Open in web view")
                }
            }
        }
    }

    @ViewBuilder
    private var resumeButton: some View {
        if let next = nextChapter {
            Button { reading = next } label: {
                Label(manga?.hasStartedReading == true ? "Resume" : "Start", systemImage: "play.fill")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .foregroundStyle(palette.onPrimary.color)
                    .background(palette.primary.color, in: Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 44)
            .padding(.bottom, 20)
            .accessibilityHint(next.name)
        }
    }

    /// Mihon's download menu: the next unread chapters, every unread one, or all.
    private func downloadMenu(_ manga: LibraryManga) -> some View {
        Menu {
            Button("Next chapter") { downloadUnread(of: manga, limit: 1) }
            Button("Next 5 chapters") { downloadUnread(of: manga, limit: 5) }
            Button("Next 10 chapters") { downloadUnread(of: manga, limit: 10) }
            Button("Unread") { downloadUnread(of: manga, limit: nil) }
            Button("All") { downloads.enqueue(manga.chapters.sorted { $0.sourceOrder > $1.sourceOrder }) }
        } label: {
            Image(systemName: "arrow.down.circle")
        }
        .accessibilityLabel("Download")
    }

    private func downloadUnread(of manga: LibraryManga, limit: Int?) {
        let unread = manga.chapters
            .filter { !$0.read && !downloads.isDownloaded($0.key) }
            .sorted { $0.sourceOrder > $1.sourceOrder }
        downloads.enqueue(limit.map { Array(unread.prefix($0)) } ?? unread)
    }

    private func startSelecting(_ chapter: ChapterRecord) {
        selection = [chapter.key]
        withAnimation { selecting = true }
    }

    private func finishSelection(_ action: () -> Void) {
        action()
        selection = []
        withAnimation { selecting = false }
    }

    private var nextChapter: ChapterRecord? { manga?.nextChapter }

    private func toggleLibrary() {
        let target = manga ?? repo.upsert(sourceId: ref.sourceId, url: ref.url, title: ref.title, cover: ref.cover)
        if target.inLibrary {
            repo.setInLibrary(target, false)
            if downloads.downloadedCount(mangaKey: target.key) > 0 { removedWithDownloads = target }
        } else if repo.addToLibrary(target, defaultCategory: defaultCategory) {
            choosingCategories = true
        }
    }

    private func refresh() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let source = try sources.source(ref.sourceId)
            let details = try await source.details(url: ref.url)
            let chapterList = try await source.chapters(url: ref.url)
            let saved = repo.upsert(sourceId: ref.sourceId, url: ref.url, details: details)
            repo.applyChapters(chapterList, to: saved)
        } catch {
            self.error = error
        }
    }

    static func statusTitle(_ status: String) -> String {
        switch status {
        case "ongoing": "Ongoing"
        case "completed": "Completed"
        case "hiatus": "On hiatus"
        case "cancelled": "Cancelled"
        default: "Unknown"
        }
    }

    static func statusIcon(_ status: String) -> String {
        switch status {
        case "ongoing": "clock"
        case "completed": "checkmark.circle"
        case "hiatus": "pause.circle"
        case "cancelled": "xmark.circle"
        default: "questionmark.circle"
        }
    }
}

private struct ActionLabel: View {
    let title: String
    let icon: String
    var active = false
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3)
            Text(title).font(.caption)
        }
        .foregroundStyle(active ? palette.primary.color : Color.secondary)
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(Rectangle())
    }
}

private struct ActionButton: View {
    let title: String
    let icon: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) { ActionLabel(title: title, icon: icon, active: active) }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.caption).frame(width: 16)
            configuration.title
        }
    }
}

private struct VerticalLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 3) {
            configuration.icon.font(.title3)
            configuration.title.font(.caption2)
        }
    }
}

/// The full cover, pinch to zoom. Save and share it; a library title can take a picture from Photos instead.
private struct CoverSheet: View {
    let url: String
    let headers: [String: String]
    let manga: LibraryManga?
    @EnvironmentObject private var repo: LibraryRepository
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var image: UIImage?
    @State private var picked: PhotosPickerItem?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            RemoteImage(url: url, headers: headers)
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .scaleEffect(scale)
                .gesture(MagnifyGesture().onChanged { scale = max(1, $0.magnification) }.onEnded { _ in withAnimation { scale = 1 } })
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    ToolbarItemGroup(placement: .bottomBar) {
                        if let image {
                            Button("Save", systemImage: "square.and.arrow.down") { save(image) }
                            let preview = Image(uiImage: image)
                            ShareLink(item: preview, preview: SharePreview("Cover", image: preview)) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                        // Like Mihon, only titles in the library can change their cover.
                        if let manga, manga.inLibrary {
                            Spacer()
                            PhotosPicker(selection: $picked, matching: .images) { Label("Edit", systemImage: "photo") }
                            if manga.customCover != nil {
                                Button("Reset", systemImage: "arrow.uturn.backward") { repo.resetCover(of: manga) }
                            }
                        }
                    }
                }
        }
        .presentationDragIndicator(.visible)
        .task(id: url) { image = try? await ImageLoader.shared.image(url, headers: headers) }
        .onChange(of: picked) { _, item in
            guard let item, let manga else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), repo.setCustomCover(data, for: manga) {
                    picked = nil
                } else {
                    message = "That picture couldn't be used as a cover."
                    picked = nil
                }
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func save(_ image: UIImage) {
        Task {
            do {
                try await PhotoSaver.save(image)
                message = "Saved to Photos."
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

/// Which scanlators' chapters to show. A ticked group is shown; unticked ones are hidden from the
/// chapter list, from Updates and from the reader's next and previous chapter.
private struct ScanlatorFilterSheet: View {
    let scanlators: [String]
    @State var excluded: Set<String>
    let save: (Set<String>) -> Void
    @Environment(\.dismiss) private var dismiss

    init(scanlators: [String], excluded: Set<String>, save: @escaping (Set<String>) -> Void) {
        self.scanlators = scanlators
        _excluded = State(initialValue: excluded)
        self.save = save
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(scanlators, id: \.self) { name in
                        Button {
                            if excluded.contains(name) { excluded.remove(name) } else { excluded.insert(name) }
                            save(excluded)
                        } label: {
                            HStack {
                                Text(name).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: excluded.contains(name) ? "square" : "checkmark.square.fill")
                                    .foregroundStyle(excluded.contains(name) ? Color.secondary : Color.accentColor)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(excluded.contains(name) ? "Hidden" : "Shown")
                    }
                } footer: {
                    Text("Chapters from unticked scanlators are hidden.")
                }
                .themedRows()
            }
            .navigationTitle("Scanlators")
            .navigationBarTitleDisplayMode(.inline)
            .themedScreen()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A note on a title; Markdown such as **bold** and links shows formatted under the description.
private struct NotesSheet: View {
    @State var notes: String
    let save: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    init(notes: String, save: @escaping (String) -> Void) {
        _notes = State(initialValue: notes)
        self.save = save
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $notes)
                .padding(.horizontal)
                .navigationTitle("Notes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            save(notes.trimmingCharacters(in: .whitespacesAndNewlines))
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
