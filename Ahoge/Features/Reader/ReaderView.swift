// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

//
//  ReaderView.swift
//  Ahoge
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ReaderView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var exportedPage: ReaderExportDocument?
    @State var pageShareImage: ReaderShareImage?
    @State var exportingPage = false
    @State var showFileExporter = false
    @State var pageExportError: String?
    @State var exportTask: Task<Void, Never>?

    let manga: Manga
    let initialChapter: Chapter
    let imagePipeline: ReaderImagePipelining

    @State var currentChapter: Chapter
    @State var pageIndex: Int
    @State private var showingSettings = false
    @State private var showingActions = false
    @State var showingChrome = false
    @State var pageLoadState: ReaderContentLoadState = .idle
    @State var retryTick = 0
    @State var pendingPageIndexAfterChapterChange: Int?
    @State var sliderActiveValue: Double? = nil
    @State private var dragInitialPageIndex: Int? = nil
    @State var activeLoadRequestID = UUID()
    @State var prefetchTask: Task<Void, Never>?
    @State var hasAppliedResumeProgress = false
    @State var canPersistPageProgress = false
    @State var pagerDisplayIndex = 1
    @State var pageImageSizes: [String: CGSize] = [:]
    @State var deferredResumePageIndex: Int?
    @State var interactionEpoch = UUID()
    @State var surfaceOwnership = ReaderSurfaceOwnership()
    @State var pendingPublication = ReaderPendingPublication<ReaderContentSnapshot, ReaderLogicalAnchor>()
    @State var surfaceInteractionStates: [String: ReaderInteractionState] = [:]
    @State var transitionState: ReaderTransitionState?
    @State var isChapterTransitioning = false
    @State var pendingVerticalScrollTarget: Int?
    @State var committedSnapshot: ReaderContentSnapshot?
    @State var readerInteractionPhase: ReaderInteractionPhase = .idle
    @State var pagerSettleTask: Task<Void, Never>?
    @State var pagerViewport = ReaderViewportMeasurement(.zero)
    @State var continuousFrames: [String: CGRect] = [:]
    @State var continuousViewportSize: CGSize = .zero
    @State var pageLuminanceByRenderItemID: [String: CGFloat] = [:]

    private let verticalScrollCoordinateSpace = "reader.vertical.scroll"
    static let chapterEndPageTarget = Int.max

    var parity: ReaderParityPreferences { model.state.readerPreferences.parity }
    var continuousPageGap: Double { isWebtoonMode ? parity.webtoonGap : parity.continuousGap }
    var shouldAnimatePages: Bool { parity.animatePages && !reduceMotion }
    var pageBackground: Color {
        switch parity.background {
        case .black: return .black
        case .white: return .white
        case .gray: return Color(white: 0.3)
        case .automatic: return readerChromeLuminance > 0.5 ? .white : .black
        }
    }
    private var colorFilter: ReaderColorFilter {
        model.state.readerPreferences.colorFilter
    }

    init(
        manga: Manga,
        initialChapter: Chapter,
        imagePipeline: ReaderImagePipelining = ReaderImagePipeline.shared
    ) {
        self.manga = manga
        self.initialChapter = initialChapter
        self.imagePipeline = imagePipeline
        _currentChapter = State(initialValue: initialChapter)
        _pageIndex = State(initialValue: 0)
    }

    var body: some View {
        ZStack {
            pageBackground.modifier(ReaderFullscreenPresentation(enabled: parity.fullscreen))

            GeometryReader { geometry in
                readerBody(in: geometry.size)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        SpatialTapGesture(count: 2).exclusively(before: SpatialTapGesture())
                            .onEnded { value in
                                if case .second(let tap) = value { handleTap(at: tap.location, in: geometry.size) }
                            }
                    )
                    .onAppear {
                        updatePagerViewportSize(geometry.size)
                    }
                    .onChange(of: geometry.size) { _, newSize in
                        updatePagerViewportSize(newSize)
                    }
            }

            if showingChrome {
                readerChrome
                    .transition(.opacity)
            }
        }
        .background(pageBackground)
        .background(ReaderDevicePresentation(orientation: model.state.readerPreferences.orientation,
                                             keepAwake: model.state.readerPreferences.keepAwake))
        .transaction { transaction in
            if !shouldAnimatePages { transaction.disablesAnimations = true }
        }
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .statusBarHidden(parity.fullscreen && !showingChrome)
        .sheet(isPresented: $showingSettings) {
            NavigationStack { ReaderSettingsView() }
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Page Actions", isPresented: $showingActions, titleVisibility: .visible) {
            ShareLink(item: "\(manga.title) • \(currentChapter.title)") {
                Label("Share Chapter", systemImage: "square.and.arrow.up")
            }
            Button("Copy Chapter Title") { }
            Button("Close", role: .cancel) { }
        }
        .sheet(item: $pageShareImage) { ReaderPageShareSheet(image: $0.image) }
        .fileExporter(isPresented: $showFileExporter, document: exportedPage, contentType: .png,
                      defaultFilename: "Page-\(pageIndex + 1)") { result in
            if case .failure(let error) = result { pageExportError = error.localizedDescription }
            exportedPage = nil
        }
        .alert("Page export unavailable", isPresented: Binding(get: { pageExportError != nil }, set: { if !$0 { pageExportError = nil } })) {
            Button("OK") { pageExportError = nil }
        } message: { Text(pageExportError ?? "The page image could not be resolved.") }
        .onAppear {
            canPersistPageProgress = false
            if let progress = model.progress(for: manga), progress.chapterID == currentChapter.id {
                pendingPageIndexAfterChapterChange = max(progress.pageIndex, 0)
            }
            startPageLoad(forceRefresh: false)
        }
        .onChange(of: pageIndex) { _, newValue in
            pendingPublication.focusChanged()
            guard !logicalPages.isEmpty else { return }
            let boundedPageIndex = boundedPageIndex(for: newValue)
            if boundedPageIndex != newValue {
                pageIndex = boundedPageIndex
                return
            }
            if canPersistPageProgress, let deferredResumePageIndex, deferredResumePageIndex != newValue {
                self.deferredResumePageIndex = nil
            }
            prefetchAroundCurrentPage()
            guard canPersistPageProgress, pageLoadState == .loaded else { return }
            persistProgress()
        }
        .onChange(of: currentChapter.id) { _, _ in
            canPersistPageProgress = false
            pageImageSizes = [:]
            deferredResumePageIndex = nil
            surfaceInteractionStates = [:]
            pageLuminanceByRenderItemID = [:]
            transitionState = nil
            pendingVerticalScrollTarget = nil
            committedSnapshot = nil
            pendingPublication = .init()
            interactionEpoch = UUID()
            continuousFrames = [:]
            surfaceOwnership = .init()
            readerInteractionPhase = .idle
            pagerSettleTask?.cancel()
            pagerSettleTask = nil
            pageIndex = boundedPageIndex(for: pendingPageIndexAfterChapterChange ?? 0)
            hasAppliedResumeProgress = false
            startPageLoad(forceRefresh: false)
        }
        .onChange(of: model.state.readerPreferences.mode) { _, _ in
            refreshCommittedSnapshot(preferredPageIndex: nil, animatedSync: false)
        }
        .onChange(of: model.state.readerPreferences.spreadBehavior) { _, _ in
            refreshCommittedSnapshot(preferredPageIndex: nil, animatedSync: false)
        }
        .onChange(of: model.state.readerPreferences.parity.invertSplitOrder) { _, _ in
            refreshCommittedSnapshot(preferredPageIndex: nil, animatedSync: false)
        }
        .onChange(of: parity.dualPageDisplay) { _, _ in
            refreshCommittedSnapshot(preferredPageIndex: nil, animatedSync: false)
        }
        .onChange(of: parity.firstPageAlone) { _, _ in
            refreshCommittedSnapshot(preferredPageIndex: nil, animatedSync: false)
        }
        .onChange(of: parity.cropBorders) { _, _ in
            refreshCommittedSnapshot(preferredPageIndex: nil, animatedSync: false)
        }
        .onChange(of: model.state.readerPreferences.parity.rotateWidePages) { _, _ in
            refreshCommittedSnapshot(preferredPageIndex: nil, animatedSync: false)
        }
        .onChange(of: model.state.readerPreferences.parity.rotateClockwise) { _, _ in
            refreshCommittedSnapshot(preferredPageIndex: nil, animatedSync: false)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, canPersistPageProgress, !logicalPages.isEmpty { persistProgress() }
        }
        .onChange(of: pagerDisplayIndex) { _, index in handlePagerDisplayIndexChange(index) }
        .onChange(of: transitionState == nil) { _, _ in flushDeferredSnapshotIfPossible() }
        .onChange(of: isChapterTransitioning) { _, _ in flushDeferredSnapshotIfPossible() }
        .onDisappear {
            interactionEpoch = UUID()
            continuousFrames = [:]
            surfaceOwnership = .init()
            surfaceInteractionStates = [:]
            pendingPublication = .init()
            activeLoadRequestID = UUID()
            prefetchTask?.cancel()
            exportTask?.cancel()
            pagerSettleTask?.cancel()
            prefetchTask = nil
            Task {
                await imagePipeline.cancelWindow(for: currentChapter.id)
            }
        }
    }

    @ViewBuilder
    private func readerBody(in rootSize: CGSize) -> some View {
        let visibilityEpoch = interactionEpoch
        if pageLoadState == .loading && currentPages.isEmpty {
            ProgressView("Loading chapter…")
                .tint(.white)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(ReaderFullscreenPresentation(enabled: parity.fullscreen))
        } else if currentPages.isEmpty {
            ReaderEmptyState(
                message: model.pageLoadError(for: currentChapter.id) ?? "No readable pages were found for this chapter.",
                retry: {
                    startPageLoad(forceRefresh: true)
                }
            )
        } else if activeReaderMode == .vertical || activeReaderMode == .webtoon {
            GeometryReader { scrollGeometry in
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            if let chapter = previousChapterForCurrentMode() {
                                ReaderTransitionPage(
                                    title: "Previous Chapter",
                                    chapterTitle: chapter.title,
                                    systemImage: chapterLeadingIcon,
                                    isEnabled: true,
                                    progress: transitionProgress(for: .previous),
                                    isLoading: isChapterTransitioning && transitionDirection == .previous,
                                    confirmLabel: "Load Previous",
                                    action: {
                                        confirmChapterTransition(.previous)
                                    }
                                )
                                .frame(minHeight: 220)
                            }

                            ForEach(Array(verticalRenderItems.enumerated()), id: \.element.id) { offset, item in
                                ReaderPageSurface(
                                    imagePipeline: imagePipeline,
                                    item: item,
                                    localFileURL: model.fileURL(for: item.page),
                                    filter: colorFilter,
                                    parity: parity,
                                    background: pageBackground,
                                    isRTL: isRTLPager,
                                    interactionEpoch: interactionEpoch,
                                    interactionVisible: visibleSurfaceIDs.contains(item.id),
                                    imageSizingMode: .fitWidth,
                                    fillViewport: false,
                                    allowsImagePan: true,
                                    allowsHighDetailAtRest: true,
                                    onImageMetadataResolved: { size in
                                        registerImageSize(size, for: item.page.id)
                                    },
                                    onLuminanceResolved: { luminance in
                                        registerPageLuminance(luminance, for: item.id)
                                    },
                                    onInteractionStateChanged: { state in
                                        updateSurfaceInteractionState(state, for: item.id)
                                    }
                                )
                                    .padding(.bottom, offset + 1 < verticalRenderItems.count && verticalRenderItems[offset + 1].logicalPageID == item.logicalPageID ? 0 : continuousPageGap)
                                    .id(pageAnchorID(for: offset))
                                    .background(
                                        GeometryReader { proxy in
                                            Color.clear.preference(
                                                key: ReaderVisiblePageFramesPreferenceKey.self,
                                                value: [item.id: proxy.frame(in: .named(verticalScrollCoordinateSpace))]
                                            )
                                        }
                                    )
                            }

                            if let chapter = nextChapterForCurrentMode() {
                                ReaderTransitionPage(
                                    title: "Next Chapter",
                                    chapterTitle: chapter.title,
                                    systemImage: chapterTrailingIcon,
                                    isEnabled: true,
                                    progress: transitionProgress(for: .next),
                                    isLoading: isChapterTransitioning && transitionDirection == .next,
                                    confirmLabel: "Load Next",
                                    action: {
                                        confirmChapterTransition(.next)
                                    }
                                )
                                .frame(minHeight: 220)
                            }
                        }
                        .padding(.horizontal, scrollGeometry.size.width * parity.sidePadding / 100)
                        .padding(.vertical, continuousPageGap)
                    }
                    .modifier(ReaderContinuousScrollLifecycle(epoch: interactionEpoch) { identity, event in
                        updateSurfaceInteractionState(ReaderInteractionState(identity: identity, event: event,
                            scale: 1, offset: .zero, edgeDirection: nil, readyDirections: []), for: identity.member)
                    })
                    .coordinateSpace(name: verticalScrollCoordinateSpace)
                    .modifier(ReaderFullscreenPresentation(enabled: parity.fullscreen))
                    .simultaneousGesture(verticalBoundaryGesture)
                    .onAppear {
                        scrollToCurrentPage(using: scrollProxy, animated: false)
                    }
                    .onPreferenceChange(ReaderVisiblePageFramesPreferenceKey.self) { frames in
                        updateVerticalPageIndex(from: frames, viewportSize: scrollGeometry.size, epoch: visibilityEpoch)
                    }
                    .onChange(of: scrollGeometry.size) { _, size in
                        updateVerticalPageIndex(from: continuousFrames, viewportSize: size, epoch: visibilityEpoch)
                    }
                    .onChange(of: currentChapter.id) { _, _ in
                        scrollToCurrentPage(using: scrollProxy, animated: false)
                    }
                    .onChange(of: retryTick) { _, _ in
                        scrollToCurrentPage(using: scrollProxy, animated: false)
                    }
                    .onChange(of: pageLoadState) { _, newState in
                        guard newState == .loaded else { return }
                        scrollToCurrentPage(using: scrollProxy, animated: false)
                    }
                    .onChange(of: pendingVerticalScrollTarget) { _, target in
                        guard target != nil else { return }
                        scrollToCurrentPage(using: scrollProxy, animated: true)
                        pendingVerticalScrollTarget = nil
                    }
                }
            }
            .id(visibilityEpoch)
        } else {
            pagedReaderBody(size: pagerViewport.layoutSize)
            .modifier(ReaderFullscreenPresentation(enabled: parity.fullscreen))
        }
    }

    private func pagedReaderBody(size: CGSize) -> some View {
        let pageWidth = max(size.width, 1)
        let pageHeight = max(size.height, 1)
        return ReaderPagedContainer(
            currentIndex: $pagerDisplayIndex,
            itemCount: pagerItems.count,
            pageWidth: activeReaderMode == .verticalPaged ? pageHeight : pageWidth,
            vertical: activeReaderMode == .verticalPaged,
            animatePages: shouldAnimatePages,
            allowsInteractivePaging: allowsInteractivePagerDragging,
            shouldCaptureDrag: { translationWidth, translationHeight in
                shouldCapturePagerDrag(translationWidth: translationWidth, translationHeight: translationHeight)
            },
            onDragChanged: { translation in
                handlePagerDragChanged(translationWidth: translation)
            },
            onDragEnded: { translation, predicted, containerWidth in
                handlePagerDragEnded(
                    translationWidth: translation,
                    predictedTranslationWidth: predicted,
                    containerWidth: containerWidth
                )
            },
            onDragCancelled: {
                settlePagerInteraction()
                resetTransitionState()
            }
        ) {
            ReaderPageStack(vertical: activeReaderMode == .verticalPaged) {
                ForEach(Array(pagerItems.enumerated()), id: \.element.id) { offset, item in
                    Group {
                        switch item {
                        case .render(let group):
                            if abs(offset - pagerDisplayIndex) <= 1 {
                            HStack(spacing: group.members.count > 1 ? 8 : 0) {
                            ForEach(group.physicalMembers(rtl: isRTLPager)) { renderItem in
                            ReaderPageSurface(
                                imagePipeline: imagePipeline,
                                item: renderItem,
                                localFileURL: model.fileURL(for: renderItem.page),
                                filter: colorFilter,
                                parity: parity,
                                background: pageBackground,
                                isRTL: isRTLPager,
                                interactionEpoch: interactionEpoch,
                                interactionVisible: offset == pagerDisplayIndex,
                                imageSizingMode: ReaderPageSizingMode(parity.scale),
                                fillViewport: true,
                                allowsImagePan: true,
                                allowsHighDetailAtRest: true,
                                onImageMetadataResolved: { size in
                                    registerImageSize(size, for: renderItem.page.id)
                                },
                                onLuminanceResolved: { luminance in
                                    registerPageLuminance(luminance, for: renderItem.id)
                                },
                                onInteractionStateChanged: { state in
                                    updateSurfaceInteractionState(state, for: renderItem.id)
                                }
                            )
                            .frame(width: group.members.count > 1 ? max((size.width - 8) / 2, 1) : size.width)
                            .accessibilityLabel("Page \(renderItem.sourcePageIndex + 1)")
                            .accessibilityAddTraits(renderItem.logicalPageIndex == pageIndex ? .isSelected : [])
                            .accessibilityAction(named: "Focus page") { pageIndex = renderItem.logicalPageIndex }
                            }
                            }
                            .environment(\.layoutDirection, .leftToRight)
                            } else { pageBackground }
                        case .previousChapter:
                            ReaderTransitionPage(
                                title: "Previous Chapter",
                                chapterTitle: previousChapterForCurrentMode()?.title,
                                systemImage: chapterLeadingIcon,
                                isEnabled: previousChapterForCurrentMode() != nil,
                                progress: transitionProgress(for: .previous),
                                isLoading: isChapterTransitioning && transitionDirection == .previous,
                                confirmLabel: "Load Previous",
                                action: {
                                    confirmChapterTransition(.previous)
                                }
                            )
                        case .nextChapter:
                            ReaderTransitionPage(
                                title: "Next Chapter",
                                chapterTitle: nextChapterForCurrentMode()?.title,
                                systemImage: chapterTrailingIcon,
                                isEnabled: nextChapterForCurrentMode() != nil,
                                progress: transitionProgress(for: .next),
                                isLoading: isChapterTransitioning && transitionDirection == .next,
                                confirmLabel: "Load Next",
                                action: {
                                    confirmChapterTransition(.next)
                                }
                            )
                        }
                    }
                    .frame(width: pageWidth, height: pageHeight)
                    .modifier(ReaderFullscreenPresentation(enabled: parity.fullscreen))
                }
            }
        }
        .modifier(ReaderFullscreenPresentation(enabled: parity.fullscreen))
        .onAppear {
            syncPagerDisplayIndex(animated: false)
        }
        .onChange(of: pageIndex) { _, _ in
            syncPagerDisplayIndex(animated: true)
        }
        .onChange(of: currentChapter.id) { _, _ in
            syncPagerDisplayIndex(animated: false)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: transitionState?.progress == 1.0) { old, new in
            return !old && new
        }
    }

    private var verticalBoundaryGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onChanged { value in
                guard isVerticalReader, !isNavigationSuspended else { return }
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                
                if dragInitialPageIndex == nil {
                    dragInitialPageIndex = pageIndex
                }
                let initialPage = dragInitialPageIndex ?? pageIndex

                if value.translation.height > 0, initialPage == 0, previousChapterForCurrentMode() != nil {
                    updateTransitionProgress(for: .previous, translationMagnitude: value.translation.height)
                } else if value.translation.height < 0, initialPage >= max(logicalPages.count - 1, 0), nextChapterForCurrentMode() != nil {
                    updateTransitionProgress(for: .next, translationMagnitude: -value.translation.height)
                } else if transitionDirection != nil {
                    resetTransitionState()
                }
            }
            .onEnded { value in
                let initialPage = dragInitialPageIndex ?? pageIndex
                dragInitialPageIndex = nil
                
                guard isVerticalReader, !isNavigationSuspended else { return }
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                
                if value.translation.height > 0, initialPage == 0, previousChapterForCurrentMode() != nil {
                    let dragMagnitude = max(value.translation.height, 0)
                    let predictedMagnitude = max(value.predictedEndTranslation.height, 0)
                    if shouldCommitBoundaryTransition(dragMagnitude: dragMagnitude, predictedMagnitude: predictedMagnitude) {
                        model.appendDiagnostic(
                            kind: .stateTransition,
                            severity: .info,
                            title: "Reader Boundary Transition",
                            message: "Committed previous chapter transition from vertical boundary gesture.",
                            errorCode: DiagnosticErrorCode.rdrVerticalTransitionCommitted.rawValue,
                            module: "ReaderGesture",
                            metadata: ["direction": "previous"]
                        )
                        confirmChapterTransition(.previous)
                    } else {
                        model.appendDiagnostic(
                            kind: .stateTransition,
                            severity: .info,
                            title: "Reader Boundary Transition",
                            message: "Cancelled previous chapter transition from vertical boundary gesture.",
                            errorCode: DiagnosticErrorCode.rdrVerticalTransitionCancelled.rawValue,
                            module: "ReaderGesture",
                            metadata: ["direction": "previous"]
                        )
                        resetTransitionState()
                    }
                } else if value.translation.height < 0, initialPage >= max(logicalPages.count - 1, 0), nextChapterForCurrentMode() != nil {
                    let dragMagnitude = max(-value.translation.height, 0)
                    let predictedMagnitude = max(-value.predictedEndTranslation.height, 0)
                    if shouldCommitBoundaryTransition(dragMagnitude: dragMagnitude, predictedMagnitude: predictedMagnitude) {
                        model.appendDiagnostic(
                            kind: .stateTransition,
                            severity: .info,
                            title: "Reader Boundary Transition",
                            message: "Committed next chapter transition from vertical boundary gesture.",
                            errorCode: DiagnosticErrorCode.rdrVerticalTransitionCommitted.rawValue,
                            module: "ReaderGesture",
                            metadata: ["direction": "next"]
                        )
                        confirmChapterTransition(.next)
                    } else {
                        model.appendDiagnostic(
                            kind: .stateTransition,
                            severity: .info,
                            title: "Reader Boundary Transition",
                            message: "Cancelled next chapter transition from vertical boundary gesture.",
                            errorCode: DiagnosticErrorCode.rdrVerticalTransitionCancelled.rawValue,
                            module: "ReaderGesture",
                            metadata: ["direction": "next"]
                        )
                        resetTransitionState()
                    }
                } else {
                    resetTransitionState()
                }
            }
    }

    private var readerChrome: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            VStack(spacing: 12) {
                chapterNavigator
                bottomBar
            }
            .padding(.bottom, 8)
        }
        .animation(.easeInOut(duration: 0.18), value: showingChrome)
    }

    private var topBar: some View {
        let close = Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.headline)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Close reader")
        let identity = VStack(alignment: .leading, spacing: 4) {
            Text(manga.title).font(.headline)
            Text(currentChapter.title).font(.subheadline)
                .foregroundStyle(readerChromeForegroundColor.opacity(0.8))
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        let actions = HStack(spacing: 8) {
            Button {
                showingActions = true
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Chapter actions")
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Reader settings")
        }
        return ReaderChromeIdentity(close: close, identity: identity, actions: actions)
        .foregroundStyle(readerChromeForegroundColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(readerBarBackground)
        .modifier(ReaderChromePresentation(foreground: readerChromeForegroundColor))
    }

    private var chapterNavigator: some View {
        let total = max(logicalPages.count, 1)
        let boundedIndex = boundedPageIndex(for: pageIndex)
        let displayedPage = sliderActiveValue != nil ? Int(sliderActiveValue!.rounded()) : (boundedIndex + 1)
        return HStack(spacing: 8) {
            Button {
                if let chapter = previousChapterForCurrentMode() {
                    transitionToChapter(chapter, pageIndex: Self.chapterEndPageTarget)
                }
            } label: {
                Image(systemName: chapterLeadingIcon)
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .background(readerCapsuleBackground, in: Circle())
            .foregroundStyle(readerChromeForegroundColor)
            .accessibilityLabel("Previous chapter")
            .disabled(previousChapterForCurrentMode() == nil)
            .opacity(previousChapterForCurrentMode() == nil ? 0.35 : 1)

            HStack(spacing: 12) {
                Text(visibleDisplayGroup?.members.count == 2 && sliderActiveValue == nil
                     ? "\(visibleDisplayGroup!.sourceRange.lowerBound + 1)–\(visibleDisplayGroup!.sourceRange.upperBound + 1)" : "\(displayedPage)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(readerChromeForegroundColor)
                    .frame(minWidth: 22, alignment: .trailing)

                if total > 1 {
                    Slider(
                        value: Binding(
                            get: { sliderActiveValue ?? Double(displayedPage) },
                            set: { value in
                                sliderActiveValue = value
                                let newIndex = max(0, min(total - 1, Int(value.rounded()) - 1))
                                if newIndex != pageIndex {
                                    pageIndex = newIndex
                                    if isVerticalReader {
                                        pendingVerticalScrollTarget = newIndex
                                    }
                                }
                            }
                        ),
                        in: 1...Double(total),
                        step: 1
                    ) { editing in
                        if !editing {
                            sliderActiveValue = nil
                        }
                    }
                    .tint(readerChromeForegroundColor)
                    .accessibilityLabel("Chapter page")
                    .accessibilityValue("Focused page \(displayedPage) of \(total)")
                } else {
                    Capsule()
                        .fill(readerPillTintColor.opacity(0.2))
                        .frame(height: 4)
                }

                Text("\(total)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(readerChromeForegroundColor)
                    .frame(minWidth: 22, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(readerCapsuleBackground, in: Capsule())

            Button {
                if let chapter = nextChapterForCurrentMode() {
                    transitionToChapter(chapter, pageIndex: 0)
                }
            } label: {
                Image(systemName: chapterTrailingIcon)
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .background(readerCapsuleBackground, in: Circle())
            .foregroundStyle(readerChromeForegroundColor)
            .accessibilityLabel("Next chapter")
            .disabled(nextChapterForCurrentMode() == nil)
            .opacity(nextChapterForCurrentMode() == nil ? 0.35 : 1)
        }
        .padding(.horizontal, 12)
    }

    private var bottomBar: some View {
        ScrollView(.vertical) {
            ReaderChromeOptions {
            ReaderBottomPill(
                systemImage: readingModeSymbol,
                title: activeReaderMode.title,
                isProminent: true,
                foregroundColor: readerChromeForegroundColor,
                backgroundTint: readerPillTintColor,
                regularBackgroundOpacity: readerPillRegularOpacity,
                prominentBackgroundOpacity: readerPillProminentOpacity
            ) {
                cycleReadingMode()
            }

            if !isVerticalReader {
                ReaderBottomPill(
                    systemImage: spreadBehaviorSymbol,
                    title: spreadBehaviorTitle,
                    foregroundColor: readerChromeForegroundColor,
                    backgroundTint: readerPillTintColor,
                    regularBackgroundOpacity: readerPillRegularOpacity,
                    prominentBackgroundOpacity: readerPillProminentOpacity
                ) {
                    toggleSpreadBehavior()
                }
            }

            ReaderBottomPill(
                systemImage: orientationSymbol,
                title: model.state.readerPreferences.orientation.rawValue.capitalized,
                foregroundColor: readerChromeForegroundColor,
                backgroundTint: readerPillTintColor,
                regularBackgroundOpacity: readerPillRegularOpacity,
                prominentBackgroundOpacity: readerPillProminentOpacity
            ) {
                cycleOrientation()
            }

            ReaderBottomPill(
                systemImage: model.state.readerPreferences.showPageNumber ? "number.circle.fill" : "number.circle",
                title: "Page",
                foregroundColor: readerChromeForegroundColor,
                backgroundTint: readerPillTintColor,
                regularBackgroundOpacity: readerPillRegularOpacity,
                prominentBackgroundOpacity: readerPillProminentOpacity
            ) {
                model.setReaderPageNumberVisible(!model.state.readerPreferences.showPageNumber)
            }
            .accessibilityValue(model.state.readerPreferences.showPageNumber ? "Page number shown" : "Page number hidden")

            ReaderBottomPill(
                systemImage: "slider.horizontal.3",
                title: "Settings",
                foregroundColor: readerChromeForegroundColor,
                backgroundTint: readerPillTintColor,
                regularBackgroundOpacity: readerPillRegularOpacity,
                prominentBackgroundOpacity: readerPillProminentOpacity
            ) {
                showingSettings = true
            }
        }
            }
        .frame(maxHeight: 220)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(readerBarBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 12)
        .modifier(ReaderChromePresentation(foreground: readerChromeForegroundColor))
    }

    private func handleTap(at point: CGPoint, in size: CGSize) {
        guard !showingSettings, !showingActions, !exportingPage else { return }
        if let group = visibleDisplayGroup, group.members.count > 1 {
            let physical = group.physicalMembers(rtl: isRTLPager)
            pageIndex = physical[point.x < size.width / 2 ? 0 : 1].logicalPageIndex
        }
        let action = parity.tapNavigation.action(x: point.x / max(size.width, 1), y: point.y / max(size.height, 1),
            rtl: isRTLPager, verticalDefault: isVerticalReader || activeReaderMode == .verticalPaged,
            invertHorizontal: parity.invertHorizontalTaps, invertVertical: parity.invertVerticalTaps)
        let intent: ReaderTapIntent
        switch action {
        case .menu: intent = .toggleChrome
        case .forward: intent = .forward
        case .backward: intent = .backward
        }
        
        switch intent {
        case .toggleChrome:
            toggleChrome()
            return
        default:
            break
        }
        
        guard !isNavigationSuspended else { return }
        
        if let transitionDirection = currentPagerTransitionDirection {
            handleTransitionTap(intent: intent, transitionDirection: transitionDirection)
            return
        }
        switch intent {
        case .forward:
            guard canRouteTapPageTurn else { return }
            advancePageForward()
        case .backward:
            guard canRouteTapPageTurn else { return }
            advancePageBackward()
        case .none, .toggleChrome:
            break
        }
    }


    

    func boundedPageIndex(for index: Int) -> Int {
        min(max(index, 0), max(logicalPages.count - 1, 0))
    }

    private func shouldCommitBoundaryTransition(dragMagnitude: CGFloat, predictedMagnitude: CGFloat) -> Bool {
        let activation = ReaderTransitionState.activationDistance
        return dragMagnitude >= activation * 0.7 || predictedMagnitude >= activation
    }



}
