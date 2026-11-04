import SwiftUI

struct ReaderView: View {
    @StateObject private var model: ReaderModel
    @EnvironmentObject private var sources: SourceManager
    @EnvironmentObject private var repo: LibraryRepository
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOverlay = false
    /// A page long-pressed for "Set as cover", waiting for confirmation.
    @State private var coverCandidate: UIImage?
    @State private var coverFailed = false
    @State private var sliderPage = 0
    @State private var scrubbing = false
    @State private var showChapters = false
    @State private var showSettings = false
    @State private var webTarget: WebTarget?
    @State private var mode: ReadingMode
    @State private var orientation: ReaderOrientation
    @State private var showModeToast = false
    @State private var showTapHint = false
    @State private var isLandscape = false
    /// Mihon's "shift": spreads start one page later, for books whose spreads are offset.
    @State private var shiftSpreads = false
    /// The screen's brightness before the reader changed it.
    @State private var savedBrightness: CGFloat?
    @State private var strip = StripScroll()
    @AppStorage(Pref.readerBackground.name) private var background = ReaderBackground.black
    @AppStorage(Pref.readerShowPageNumber.name) private var showPageNumber = true
    @AppStorage(Pref.readerKeepScreenOn.name) private var keepScreenOn = true
    @AppStorage(Pref.readerBrightness.name) private var brightness = 0
    @AppStorage(Pref.readerTapLayout.name) private var tapLayout = TapZoneLayout.standard
    @AppStorage(Pref.readerInvertTaps.name) private var invertTaps = false
    @AppStorage(Pref.readerShowTapZones.name) private var showTapZones = true
    @AppStorage(Pref.readerShowModeToast.name) private var showModeOnOpen = true
    @AppStorage(Pref.readerDrawUnderCutout.name) private var drawUnderCutout = true
    @AppStorage(Pref.readerWebtoonPadding.name) private var webtoonPadding = 0.0
    @AppStorage(Pref.readerWebtoonGap.name) private var webtoonGap = false
    @AppStorage(Pref.readerHideMenuOnScroll.name) private var hideMenuOnScroll = 2
    @AppStorage(Pref.readerCropBordersPaged.name) private var cropPaged = false
    @AppStorage(Pref.readerCropBordersWebtoon.name) private var cropWebtoon = false
    @AppStorage(Pref.readerScaleType.name) private var scaleType = ReaderScaleType.fitScreen
    @AppStorage(Pref.readerZoomStart.name) private var zoomStart = ReaderZoomStart.auto
    @AppStorage(Pref.readerWidePages.name) private var widePages = WidePageMode.off
    @AppStorage(Pref.readerInvertSplit.name) private var invertSplit = false
    @AppStorage(Pref.readerDualPage.name) private var dualPage = DualPageMode.off
    @AppStorage(Pref.readerDoubleTapZoom.name) private var doubleTapZoom = true
    @AppStorage(Pref.readerDisableZoomOut.name) private var disableZoomOut = false
    @AppStorage(Pref.readerDoubleTapSpeed.name) private var doubleTapSpeed = 1
    @AppStorage(Pref.readerColorFilter.name) private var colorFilter = false
    @AppStorage(Pref.readerColorFilterColor.name) private var colorFilterColor = Pref.readerColorFilterColor.defaultValue
    @AppStorage(Pref.readerColorFilterMode.name) private var colorFilterMode = ColorFilterMode.normal
    @AppStorage(Pref.readerGrayscale.name) private var grayscale = false
    @AppStorage(Pref.readerInvertColors.name) private var invertColors = false
    @AppStorage(Pref.readerAlwaysShowTransition.name) private var alwaysShowTransition = true
    private let start: ChapterRecord

    init(sourceId: String, manga: LibraryManga, chapter: ChapterRecord) {
        start = chapter
        _model = StateObject(wrappedValue: ReaderModel(sourceId: sourceId, manga: manga, start: chapter))
        _mode = State(initialValue: ReadingMode.load(for: manga.key))
        _orientation = State(initialValue: ReaderOrientation.load(for: manga.key))
    }

    var body: some View {
        ZStack {
            background.color
                .ignoresSafeArea()
                .onTapGesture { toggleOverlay() }
            content
                .id(mode)
                .opacity(model.ready ? 1 : 0)
                .ignoresSafeArea(.container, edges: drawUnderCutout ? .all : .bottom)
            if !model.ready && model.error == nil {
                ProgressView().tint(background.foreground)
            } else if let error = model.error, model.sections.isEmpty {
                ErrorStateView(error: error, retry: { Task { await model.open(model.currentChapter, provider: pages) } })
                    .foregroundStyle(background.foreground)
            }
            filters
            if showTapHint, mode.isPaged {
                TapZoneOverlay(layout: tapLayout, mirrored: mode == .rightToLeft, inverted: invertTaps)
                    .transition(.opacity)
            }
            if showModeToast { modeToast.transition(.opacity) }
        }
        .background { keyCommands }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { isLandscape = proxy.size.width > proxy.size.height }
                    .onChange(of: proxy.size) { _, size in isLandscape = size.width > size.height }
            }
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
        .alert("Set as cover?", isPresented: Binding(get: { coverCandidate != nil }, set: { if !$0 { coverCandidate = nil } })) {
            Button("Set as cover") {
                if let image = coverCandidate { setCover(image) }
                coverCandidate = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This page becomes the cover of \(model.manga.title).")
        }
        .alert("Couldn't set cover", isPresented: $coverFailed) {
            Button("OK", role: .cancel) {}
        }
        .statusBarHidden(!showOverlay)
        .persistentSystemOverlays(showOverlay ? .automatic : .hidden)
        // The reader is dark whatever the app theme, so its bars and text keep their contrast.
        .preferredColorScheme(.dark)
        .task {
            guard model.sections.isEmpty else { return }
            await model.open(start, provider: pages)
        }
        .task { await flashHints(tapZones: true) }
        .onChange(of: model.position) { model.positionChanged(repo: repo, provider: pages) }
        .onChange(of: model.ready) { _, ready in
            if ready, model.error == nil { repo.recordHistory(model.currentChapter); model.startClock() }
        }
        .onChange(of: model.currentChapter.key) { _, _ in
            if model.ready { repo.recordHistory(model.currentChapter); model.restartClock(repo: repo) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.startClock() } else { model.stopClock(repo: repo) }
        }
        .onChange(of: model.currentPage) { _, page in if !scrubbing { sliderPage = page } }
        .onChange(of: sliderPage) { _, page in
            // Paged modes follow the slider live; a webtoon jumps when it is let go.
            if scrubbing, mode.isPaged { model.jump(to: page) }
        }
        .onChange(of: mode) { _, mode in
            mode.save(for: model.manga.key)
            Task { await model.reposition() }
            Task { await flashHints(tapZones: false) }
        }
        .onChange(of: layout, initial: true) { old, new in
            model.layout = new
            if old != new { Task { await model.reposition() } }
        }
        .onChange(of: pageTransform(paged: mode.isPaged), initial: true) { _, transform in model.transform = transform }
        .onChange(of: orientation) { _, orientation in
            orientation.save(for: model.manga.key)
            OrientationLock.apply(orientation.mask(current: OrientationLock.current))
        }
        .onChange(of: brightness) { applyBrightness() }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = keepScreenOn
            model.excludedScanlators = repo.excludedScanlators(mangaKey: model.manga.key)
            OrientationLock.apply(orientation.mask(current: OrientationLock.current))
            applyBrightness()
        }
        .onDisappear {
            model.stopClock(repo: repo)
            UIApplication.shared.isIdleTimerDisabled = false
            restoreBrightness()
            // Back to every orientation, like the window style below.
            OrientationLock.apply(.all)
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
        .sheet(isPresented: $showSettings) { ReaderSettingsSheet(mode: $mode, orientation: $orientation) }
        .sheet(item: $webTarget) { WebViewSheet(target: $0) }
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

    /// The reading mode for a moment on open, and the tap zones with it (Mihon's hints).
    private func flashHints(tapZones: Bool) async {
        withAnimation(.easeOut(duration: 0.2)) {
            showModeToast = showModeOnOpen
            showTapHint = tapZones && showTapZones && mode.isPaged && tapLayout != .disabled
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        withAnimation(.easeOut(duration: 0.3)) {
            showModeToast = false
            showTapHint = false
        }
    }

    // MARK: Settings in effect

    /// Two pages side by side: horizontal paged modes, always or in landscape.
    private var dualActive: Bool {
        guard mode == .leftToRight || mode == .rightToLeft else { return false }
        switch dualPage {
        case .off: return false
        case .always: return true
        case .landscape: return isLandscape
        }
    }

    private var layout: ReaderModel.Layout {
        ReaderModel.Layout(
            splitWide: mode.isPaged && widePages == .split && !dualActive,
            dualPage: dualActive,
            rightToLeft: mode == .rightToLeft,
            shiftSpreads: shiftSpreads,
            alwaysShowTransition: alwaysShowTransition
        )
    }

    private func pageTransform(paged: Bool, half: ImageTransform.Half? = nil) -> ImageTransform {
        ImageTransform(
            cropBorders: paged ? cropPaged : cropWebtoon,
            half: half,
            splitRightToLeft: half != nil && (mode == .rightToLeft) != invertSplit,
            rotateWide: paged && widePages == .rotate && !dualActive,
            grayscale: grayscale,
            invert: invertColors
        )
    }

    private func zoomOptions(alignment: CGFloat = 0.5) -> ZoomOptions {
        ZoomOptions(
            scale: scaleType,
            start: zoomStart,
            rightToLeft: mode == .rightToLeft,
            panWide: widePages == .pan && !dualActive,
            doubleTapZoom: doubleTapZoom,
            disableZoomOut: disableZoomOut,
            doubleTapDuration: doubleTapSpeed == 0 ? 0 : doubleTapSpeed == 2 ? 0.15 : 0.3,
            horizontalAlignment: alignment
        )
    }

    // MARK: Brightness and colour

    @ViewBuilder private var filters: some View {
        if brightness < 0 {
            Color.black.opacity(Double(-brightness) / 100)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        if colorFilter {
            FilterColor.color(colorFilterColor)
                .blendMode(colorFilterMode.blendMode)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private var screen: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
    }

    /// Above 0 the screen itself gets brighter or darker; its own brightness comes back on close.
    private func applyBrightness() {
        guard brightness > 0 else { return restoreBrightness() }
        guard let screen else { return }
        if savedBrightness == nil { savedBrightness = screen.brightness }
        screen.brightness = CGFloat(brightness) / 100
    }

    private func restoreBrightness() {
        guard let saved = savedBrightness else { return }
        screen?.brightness = saved
        savedBrightness = nil
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

    private static let stripSpace = "strip"

    private var webtoon: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(spacing: webtoonGap ? 12 : 0) {
                    ForEach(model.items) { item(for: $0, paged: false) }
                }
                .padding(.horizontal, geometry.size.width * webtoonPadding)
                .background {
                    GeometryReader { stack in
                        Color.clear.preference(key: StripOffsetKey.self, value: stack.frame(in: .named(Self.stripSpace)).minY)
                    }
                }
                .scrollTargetLayout()
            }
            .coordinateSpace(.named(Self.stripSpace))
            .scrollPosition(id: $model.position)
            .scrollIndicators(.hidden)
            .contentShape(Rectangle())
            .onTapGesture { toggleOverlay() }
            .onPreferenceChange(StripOffsetKey.self) { stripMoved(to: $0) }
        }
    }

    /// "Hide menu on scroll": the menu closes once the strip moves far enough while it is open.
    private func stripMoved(to offset: CGFloat) {
        guard showOverlay, hideMenuOnScroll > 0 else {
            strip.anchor = nil
            return
        }
        guard let anchor = strip.anchor else {
            strip.anchor = offset
            return
        }
        let distance: [CGFloat] = [0, 160, 80, 30]
        if abs(offset - anchor) > distance[min(hideMenuOnScroll, 3)] {
            strip.anchor = nil
            toggleOverlay()
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
            if item.spread.isEmpty {
                ReaderPageView(
                    page: page, index: index, paged: paged, foreground: background.foreground,
                    transform: pageTransform(paged: paged, half: item.half), zoom: zoomOptions(),
                    onTap: pagedTap, onSize: sizeReporter(item.chapter, index), onSetCover: setCoverAction
                )
            } else {
                spread(item)
            }
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

    /// Two pages side by side, meeting in the middle. Already in screen order, so always laid out left to right.
    private func spread(_ item: ReaderModel.Item) -> some View {
        HStack(spacing: 0) {
            ForEach(item.spread.indices, id: \.self) { slot in
                let side = item.spread[slot]
                ReaderPageView(
                    page: side.page, index: side.index, paged: true, foreground: background.foreground,
                    transform: pageTransform(paged: true), zoom: zoomOptions(alignment: slot == 0 ? 1 : 0),
                    onTap: { point in pagedTap(CGPoint(x: (point.x + CGFloat(slot)) / 2, y: point.y)) },
                    onSize: sizeReporter(item.chapter, side.index), onSetCover: setCoverAction
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func setCover(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.95), repo.setCustomCover(data, for: model.manga) else {
            coverFailed = true
            return
        }
    }

    /// Only titles in the library can take a new cover (Mihon's rule).
    private var setCoverAction: ((UIImage) -> Void)? {
        model.manga.inLibrary ? { coverCandidate = $0 } : nil
    }

    private func sizeReporter(_ chapter: ChapterRecord, _ index: Int) -> (CGSize) -> Void {
        let id = ReaderModel.pageID(chapter.url, index)
        return { size in model.learnSize(size, of: id) }
    }

    /// A tap on a paged page, at `point` (0...1 across the screen), through the tap zone layout.
    /// Right to left mirrors the zones, so the side pages turn towards still turns them on.
    private func pagedTap(_ point: CGPoint) {
        let mirrored = mode == .rightToLeft ? CGPoint(x: 1 - point.x, y: point.y) : point
        switch TapZones.action(at: mirrored, size: CGSize(width: 1, height: 1), layout: tapLayout, inverted: invertTaps) {
        case .menu: toggleOverlay()
        case .previous: turn(-1)
        case .next: turn(1)
        }
    }

    /// Moves `step` items on in reading order.
    private func turn(_ step: Int) {
        if showOverlay { toggleOverlay() }
        guard let target = model.item(offset: step) else { return }
        withAnimation(.easeInOut(duration: 0.25)) { model.position = target }
    }

    /// Left and right arrows move the way the pages lie on screen.
    private func turnOnScreen(_ step: Int) { turn(mode == .rightToLeft ? -step : step) }

    /// Hardware keyboard: arrows and space turn pages, [ and ] change chapter.
    private var keyCommands: some View {
        Group {
            Button("Previous page") { turnOnScreen(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("Next page") { turnOnScreen(1) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("Previous page") { turn(-1) }.keyboardShortcut(.upArrow, modifiers: [])
            Button("Next page") { turn(1) }.keyboardShortcut(.downArrow, modifiers: [])
            Button("Next page") { turn(1) }.keyboardShortcut(.space, modifiers: [])
            Button("Previous page") { turn(-1) }.keyboardShortcut(.space, modifiers: .shift)
            Button("Previous chapter") { open(model.chapter(before: model.currentChapter)) }.keyboardShortcut("[", modifiers: [])
            Button("Next chapter") { open(model.chapter(after: model.currentChapter)) }.keyboardShortcut("]", modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
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

    private var modeToast: some View {
        Label(mode.title, systemImage: mode.icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.7), in: Capsule())
            .allowsHitTesting(false)
    }

    private var barBackground: some View {
        Rectangle().fill(.ultraThinMaterial).overlay(Color.black.opacity(0.72))
    }

    private var currentImage: UIImage? {
        guard let pages = model.currentSection?.pages, pages.indices.contains(model.currentPage) else { return nil }
        return ImageMemoryCache.shared[pages[model.currentPage].url]
    }

    /// The chapter on the source's website.
    private var chapterWebURL: String? {
        sources.installed(model.sourceId).flatMap { $0.baseUrl.isEmpty ? nil : $0 }.map { model.currentChapter.webURL(baseUrl: $0.baseUrl) }
    }

    private var topBar: some View {
        let bookmarked = model.currentChapter.bookmark
        return HStack(spacing: 6) {
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
            iconButton(bookmarked ? "bookmark.fill" : "bookmark", label: bookmarked ? "Remove bookmark" : "Bookmark chapter") {
                repo.setBookmark([model.currentChapter], !bookmarked)
            }
            if let image = currentImage {
                let preview = Image(uiImage: image)
                ShareLink(item: preview, preview: SharePreview(model.currentChapter.name, image: preview)) {
                    icon("square.and.arrow.up")
                }
                .accessibilityLabel("Share page")
            }
            if let web = chapterWebURL {
                Menu {
                    Button("Open in WebView", systemImage: "globe") { webTarget = WebTarget(url: web) }
                    if let url = URL(string: web) {
                        Button("Open in browser", systemImage: "safari") { openURL(url) }
                    }
                } label: {
                    icon("ellipsis.circle")
                }
                .accessibilityLabel("More")
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
                if dualActive {
                    toolButton("rectangle.split.2x1", title: "Shift") { shiftSpreads.toggle() }
                        .accessibilityLabel("Shift pages by one")
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

/// Where the webtoon strip was when the menu opened. A reference, so following the scroll never redraws the reader.
private final class StripScroll {
    var anchor: CGFloat?
}

/// The webtoon strip's top edge in its scroll view, for "Hide menu on scroll".
private struct StripOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

extension Notification.Name {
    /// Posted when the reader goes away, so the root view can reassert the window style.
    static let readerDidClose = Notification.Name("ahoge.readerDidClose")
}
