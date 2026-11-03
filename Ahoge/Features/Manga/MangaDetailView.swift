import SwiftUI

struct MangaDetailView: View {
    let ref: MangaRef
    @EnvironmentObject private var sources: SourceManager
    @EnvironmentObject private var repo: LibraryRepository
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

    init(ref: MangaRef) {
        self.ref = ref
        let key = LibraryManga.makeKey(sourceId: ref.sourceId, url: ref.url)
        _display = State(initialValue: ChapterDisplay.load(for: key))
    }

    private var manga: LibraryManga? { repo.manga(sourceId: ref.sourceId, url: ref.url) }
    private var info: InstalledSource? { sources.installed(ref.sourceId) }
    private var headers: [String: String] { info.map { ["Referer": $0.baseUrl + "/"] } ?? [:] }
    private var cover: String { manga?.coverUrl.nonEmpty ?? ref.cover }
    private var webURL: String? {
        guard let info else { return nil }
        if let manga { return manga.webURL(baseUrl: info.baseUrl) }
        return LibraryManga(sourceId: ref.sourceId, url: ref.url, title: ref.title, coverUrl: "").webURL(baseUrl: info.baseUrl)
    }

    var body: some View {
        let chapters = manga.map { display.apply(to: $0.chapters) } ?? []
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
            if manga?.lastChapterFetch == nil { await refresh() }
        }
        .onChange(of: display) { _, value in value.save(for: LibraryManga.makeKey(sourceId: ref.sourceId, url: ref.url)) }
        .toolbar { toolbarItems(chapters) }
        .sheet(item: $webTarget) { WebViewSheet(target: $0) }
        .sheet(isPresented: $showCover) { CoverSheet(url: cover, headers: headers) }
        .sheet(isPresented: $choosingCategories) {
            if let manga { SetCategoriesSheet(manga: [manga]) }
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
                    if let author = manga?.author.nonEmpty { Label(author, systemImage: "person").font(.subheadline) }
                    if let artist = manga?.artist.nonEmpty, artist != manga?.author {
                        Label(artist, systemImage: "paintbrush").font(.subheadline)
                    }
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
            if let webURL {
                ActionButton(title: "WebView", icon: "globe") { webTarget = WebTarget(url: webURL) }
            }
        }
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
        HStack {
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
                if !display.isDefault {
                    Button("Reset", systemImage: "arrow.counterclockwise") { display = ChapterDisplay() }
                }
            } label: {
                Image(systemName: display.isDefault ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
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
            ChapterRow(chapter: chapter)
        } else {
            Button { reading = chapter } label: { ChapterRow(chapter: chapter) }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading) {
                    Button(chapter.read ? "Unread" : "Read", systemImage: chapter.read ? "eye.slash" : "eye") { repo.setRead([chapter], !chapter.read) }
                        .tint(Color(uiColor: UIColor(rgb: palette.primary.light))) // UIKit draws swipe labels white
                }
                .contextMenu {
                    Button("Select", systemImage: "checkmark.circle") { startSelecting(chapter) }
                    Button(chapter.read ? "Mark as unread" : "Mark as read", systemImage: chapter.read ? "eye.slash" : "eye") {
                        repo.setRead([chapter], !chapter.read)
                    }
                    Button("Mark previous as read", systemImage: "arrow.down.to.line") { repo.markPreviousRead(chapter, in: manga) }
                }
        }
    }

    private func selectionBar(_ manga: LibraryManga) -> some View {
        let chosen = manga.chapters.filter { selection.contains($0.key) }
        return HStack {
            Button("Read", systemImage: "eye") { finishSelection { repo.setRead(chosen, true) } }
            Spacer()
            Button("Unread", systemImage: "eye.slash") { finishSelection { repo.setRead(chosen, false) } }
            Spacer()
            Button("Previous read", systemImage: "arrow.down.to.line") {
                // The newest selected chapter and everything older.
                finishSelection { if let newest = chosen.min(by: { $0.sourceOrder < $1.sourceOrder }) { repo.markPreviousRead(newest, in: manga) } }
            }
        }
        .labelStyle(VerticalLabelStyle())
        .disabled(chosen.isEmpty)
        .padding(.horizontal, 28)
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

/// The full cover, pinch to zoom.
private struct CoverSheet: View {
    let url: String
    let headers: [String: String]
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        NavigationStack {
            RemoteImage(url: url, headers: headers)
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .scaleEffect(scale)
                .gesture(MagnifyGesture().onChanged { scale = max(1, $0.magnification) }.onEnded { _ in withAnimation { scale = 1 } })
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDragIndicator(.visible)
    }
}
