import SwiftUI

struct ReaderView: View {
    @StateObject private var model: ReaderModel
    @EnvironmentObject private var sources: SourceManager
    @EnvironmentObject private var repo: LibraryRepository
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss
    @State private var showOverlay = false
    @State private var sliderPage = 0
    @State private var scrubbing = false
    @State private var showChapters = false
    @State private var showSettings = false
    @State private var mode: ReadingMode
    @AppStorage(Pref.readerBackground.name) private var background = ReaderBackground.black
    @AppStorage(Pref.readerShowPageNumber.name) private var showPageNumber = true
    @AppStorage(Pref.readerKeepScreenOn.name) private var keepScreenOn = true
    @AppStorage(Pref.readerDim.name) private var dim = 0.0
    @AppStorage(Pref.readerTapZones.name) private var tapZones = true
    @AppStorage(Pref.readerInvertTaps.name) private var invertTaps = false
    @AppStorage(Pref.readerWebtoonPadding.name) private var webtoonPadding = 0.0
    @AppStorage(Pref.readerWebtoonGap.name) private var webtoonGap = false
    private let start: ChapterRecord

    init(sourceId: String, manga: LibraryManga, chapter: ChapterRecord) {
        start = chapter
        _model = StateObject(wrappedValue: ReaderModel(sourceId: sourceId, manga: manga, start: chapter))
        _mode = State(initialValue: ReadingMode.load(for: manga.key))
    }

    var body: some View {
        ZStack {
            background.color
                .ignoresSafeArea()
                .onTapGesture { toggleOverlay() }
            content
                .id(mode)
                .opacity(model.ready ? 1 : 0)
                .ignoresSafeArea()
            if !model.ready && model.error == nil {
                ProgressView().tint(background.foreground)
            } else if let error = model.error, model.sections.isEmpty {
                ErrorStateView(error: error, retry: { Task { await model.open(model.currentChapter, provider: pages) } })
                    .foregroundStyle(background.foreground)
            }
            Color.black.opacity(dim)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            if !showOverlay, showPageNumber, model.ready, pageCount > 0 { pageNumber }
        }
        .overlay(alignment: .top) {
            if showOverlay { topBar.transition(.move(edge: .top).combined(with: .opacity)) }
        }
        .overlay(alignment: .bottom) {
            if showOverlay { bottomBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .statusBarHidden(!showOverlay)
        .persistentSystemOverlays(showOverlay ? .automatic : .hidden)
        // The reader is dark whatever the app theme, so its bars and text keep their contrast.
        .preferredColorScheme(.dark)
        .task {
            guard model.sections.isEmpty else { return }
            await model.open(start, provider: pages)
        }
        .onChange(of: model.position) { model.positionChanged(repo: repo, provider: pages) }
        .onChange(of: model.ready) { _, ready in
            if ready, model.error == nil { repo.recordHistory(model.currentChapter) }
        }
        .onChange(of: model.currentChapter.key) { _, _ in
            if model.ready { repo.recordHistory(model.currentChapter) }
        }
        .onChange(of: model.currentPage) { _, page in if !scrubbing { sliderPage = page } }
        .onChange(of: sliderPage) { _, page in
            // Paged modes follow the slider live; a webtoon jumps when it is let go.
            if scrubbing, mode.isPaged { model.jump(to: page) }
        }
        .onChange(of: mode) { _, mode in
            mode.save(for: model.manga.key)
            Task { await model.reposition() }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepScreenOn }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            downloads.readerClosed()
            NotificationCenter.default.post(name: .readerDidClose, object: nil)
        }
        .onChange(of: keepScreenOn) { _, on in UIApplication.shared.isIdleTimerDisabled = on }
        .sheet(isPresented: $showChapters) {
            ReaderChapterList(manga: model.manga, current: model.currentChapter) { chapter in
                Task { await model.open(chapter, provider: pages) }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showSettings) { ReaderSettingsSheet(mode: $mode) }
    }

    private var pageCount: Int { model.currentSection?.pages.count ?? 0 }
    private var pages: PageProvider { PageProvider(sources: sources, downloads: downloads) }

    private func toggleOverlay() {
        withAnimation(.easeInOut(duration: 0.22)) { showOverlay.toggle() }
    }

    private func open(_ chapter: ChapterRecord?) {
        guard let chapter else { return }
        Task { await model.open(chapter, provider: pages) }
    }

    // MARK: Pages

    @ViewBuilder private var content: some View {
        switch mode {
        case .webtoon: webtoon
        case .leftToRight: pager(.horizontal).environment(\.layoutDirection, .leftToRight)
        case .rightToLeft: pager(.horizontal).environment(\.layoutDirection, .rightToLeft)
        case .vertical: pager(.vertical)
        }
    }

    private var webtoon: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(spacing: webtoonGap ? 12 : 0) {
                    ForEach(model.items) { item(for: $0, paged: false) }
                }
                .padding(.horizontal, geometry.size.width * webtoonPadding)
                .scrollTargetLayout()
            }
            .scrollPosition(id: $model.position)
            .scrollIndicators(.hidden)
            .contentShape(Rectangle())
            .onTapGesture { toggleOverlay() }
        }
    }

    private func pager(_ axis: Axis) -> some View {
        ScrollView(axis == .horizontal ? .horizontal : .vertical) {
            Group {
                if axis == .horizontal {
                    LazyHStack(spacing: 0) { pagerItems }
                } else {
                    LazyVStack(spacing: 0) { pagerItems }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $model.position)
        .scrollIndicators(.hidden)
    }

    private var pagerItems: some View {
        ForEach(model.items) {
            item(for: $0, paged: true).containerRelativeFrame([.horizontal, .vertical])
        }
    }

    @ViewBuilder private func item(for item: ReaderModel.Item, paged: Bool) -> some View {
        switch item.kind {
        case .page(let page, let index, _):
            ReaderPageView(page: page, index: index, paged: paged, foreground: background.foreground, onTap: pagedTap)
        case .start, .end:
            ReaderTransitionView(
                item: item,
                foreground: background.foreground,
                isLoadingNext: model.isLoadingNext,
                error: model.error,
                openPrevious: { open($0) },
                retry: { model.retryNext(provider: pages) }
            )
            .environment(\.layoutDirection, .leftToRight)
            .frame(maxWidth: .infinity, maxHeight: paged ? .infinity : nil)
            .contentShape(Rectangle())
            .onTapGesture { toggleOverlay() }
        }
    }

    /// A tap on a paged page, at `point` (0...1 across the screen): the outer thirds turn the page.
    private func pagedTap(_ point: CGPoint) {
        let along = mode == .vertical ? point.y : point.x
        var step = along < 1 / 3 ? -1 : along > 2 / 3 ? 1 : 0
        if mode == .rightToLeft { step = -step }
        if invertTaps { step = -step }
        guard tapZones, step != 0 else { return toggleOverlay() }
        if showOverlay { toggleOverlay() }
        guard let target = model.item(offset: step) else { return }
        withAnimation(.easeInOut(duration: 0.25)) { model.position = target }
    }

    // MARK: Overlay

    private var pageNumber: some View {
        Text("\(model.currentPage + 1) / \(pageCount)")
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.black.opacity(0.6), in: Capsule())
            .padding(.bottom, 4)
            .allowsHitTesting(false)
    }

    private var barBackground: some View {
        Rectangle().fill(.ultraThinMaterial).overlay(Color.black.opacity(0.72))
    }

    private var currentImage: UIImage? {
        guard let pages = model.currentSection?.pages, pages.indices.contains(model.currentPage) else { return nil }
        return ImageMemoryCache.shared[pages[model.currentPage].url]
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            iconButton("chevron.backward", label: "Close") { dismiss() }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.manga.title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                Text(model.currentChapter.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            if let image = currentImage {
                let preview = Image(uiImage: image)
                ShareLink(item: preview, preview: SharePreview(model.currentChapter.name, image: preview)) {
                    icon("square.and.arrow.up")
                }
                .accessibilityLabel("Share page")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background { barBackground.ignoresSafeArea(edges: .top) }
    }

    private var bottomBar: some View {
        let previous = model.chapter(before: model.currentChapter)
        let next = model.chapter(after: model.currentChapter)
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                roundButton("backward.end.fill", label: "Previous chapter", enabled: previous != nil) { open(previous) }
                HStack(spacing: 12) {
                    Text("\(sliderPage + 1)").frame(minWidth: 22)
                    if pageCount > 1 {
                        PageSlider(page: $sliderPage, count: pageCount, reversed: mode == .rightToLeft) { editing in
                            scrubbing = editing
                            if !editing { model.jump(to: sliderPage) }
                        }
                    } else {
                        Spacer()
                    }
                    Text("\(pageCount)").frame(minWidth: 22)
                }
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(Capsule().fill(.ultraThinMaterial).overlay(Capsule().fill(Color.black.opacity(0.72))))
                roundButton("forward.end.fill", label: "Next chapter", enabled: next != nil) { open(next) }
            }
            // Right to left reads the slider and the chapter buttons the other way round, like the pages.
            .environment(\.layoutDirection, mode == .rightToLeft ? .rightToLeft : .leftToRight)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            HStack {
                Menu {
                    Picker("Reading mode", selection: $mode) {
                        ForEach(ReadingMode.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                    }
                } label: {
                    toolLabel(mode.icon, title: "Mode")
                }
                toolButton("list.bullet", title: "Chapters") { showChapters = true }
                toolButton("gearshape", title: "Settings") { showSettings = true }
            }
            .padding(.top, 8)
            .padding(.bottom, 2)
            .background { barBackground.ignoresSafeArea(edges: .bottom) }
        }
        .onAppear { sliderPage = model.currentPage }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private func iconButton(_ name: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { icon(name) }.accessibilityLabel(label)
    }

    private func roundButton(_ name: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? 1 : 0.3))
                .frame(width: 48, height: 48)
                .background(Circle().fill(.ultraThinMaterial).overlay(Circle().fill(Color.black.opacity(0.72))))
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func toolLabel(_ name: String, title: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: name).font(.system(size: 18, weight: .medium))
            Text(title).font(.caption2.weight(.medium))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }

    private func toolButton(_ name: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { toolLabel(name, title: title) }
    }
}

extension Notification.Name {
    /// Posted when the reader goes away, so the root view can reassert the window style.
    static let readerDidClose = Notification.Name("ahoge.readerDidClose")
}
