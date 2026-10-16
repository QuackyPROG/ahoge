// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

//
//  ReaderView+SnapshotLifecycle.swift
//  Ahoge
//

import SwiftUI

extension ReaderView {
    func buildReaderSnapshot(
        mode: ReaderMode? = nil,
        pages: [ReaderPage]? = nil,
        imageSizes: [String: CGSize]? = nil
    ) -> ReaderContentSnapshot {
        let resolvedMode = mode ?? model.state.readerPreferences.mode
        let resolvedPages = pages ?? liveResolvedPages
        let resolvedImageSizes = imageSizes ?? pageImageSizes
        let data = ReaderRenderData.build(
                pages: resolvedPages,
                mode: resolvedMode,
                spreadBehavior: model.state.readerPreferences.spreadBehavior,
                imageSizes: resolvedImageSizes,
                pagerViewportSize: nil,
                invertSplitOrder: model.state.readerPreferences.parity.invertSplitOrder,
                rotateWidePages: model.state.readerPreferences.parity.rotateWidePages,
                rotateClockwise: model.state.readerPreferences.parity.rotateClockwise
            )
        return ReaderContentSnapshot(
            chapterID: currentChapter.id, mode: resolvedMode, pages: resolvedPages,
            imageSizes: resolvedImageSizes, renderData: data,
            displayGroups: ReaderDisplayGroup.build(data: data, mode: resolvedMode, sizes: resolvedImageSizes,
                policy: parity.dualPageDisplay, firstPageAlone: parity.firstPageAlone, viewport: pagerViewportSizeForRendering)
        )
    }

    func refreshCommittedSnapshot(preferredPageIndex: Int?, animatedSync: Bool) {
        requestSnapshot(buildReaderSnapshot(), preferredPageIndex: preferredPageIndex, animatedSync: animatedSync)
    }

    func requestSnapshot(_ snapshot: ReaderContentSnapshot, preferredPageIndex: Int?, animatedSync: Bool) {
        guard snapshot.chapterID == currentChapter.id else { return }
        let explicitAnchor = preferredPageIndex.flatMap { index in
            snapshot.renderData.anchor(for: min(max(index, 0), max(snapshot.renderData.logicalPages.count - 1, 0)))
        }
        pendingPublication.request(snapshot, chapter: snapshot.chapterID, anchor: explicitAnchor,
            chapterEnd: preferredPageIndex == Self.chapterEndPageTarget)
        publishPendingSnapshot(animatedSync: animatedSync)
    }

    func commitSnapshot(_ snapshot: ReaderContentSnapshot, preferredAnchor: ReaderLogicalAnchor?, chapterEnd: Bool, animatedSync: Bool) {
        let previousIndex = pageIndex
        let anchor = preferredAnchor ?? committedSnapshot?.renderData.anchor(for: pageIndex)
        if committedSnapshot?.mode != snapshot.mode {
            // Mode changes replace the host graph only after publication is idle.
            // An old graph's terminal/register callback must not affect the new one.
            interactionEpoch = UUID()
            continuousFrames = [:]
            surfaceOwnership = .init()
            surfaceInteractionStates = [:]
        }
        committedSnapshot = snapshot
        let resolvedIndex: Int
        if chapterEnd { resolvedIndex = max(snapshot.renderData.logicalPages.count - 1, 0) }
        else if let anchor, let mappedIndex = snapshot.renderData.index(for: anchor) { resolvedIndex = mappedIndex }
        else { resolvedIndex = min(max(pageIndex, 0), max(snapshot.renderData.logicalPages.count - 1, 0)) }
        pageIndex = resolvedIndex
        syncPagerDisplayIndex(animated: animatedSync)
        reconcileSurfaceInteractions()
        // An index change is persisted by the single pageIndex observer.
        if previousIndex == resolvedIndex, canPersistPageProgress, pageLoadState == .loaded { persistProgress() }
    }

    func publishPendingSnapshot(animatedSync: Bool) {
        guard let (snapshot, anchor, chapterEnd) = pendingPublication.take(chapter: currentChapter.id, gate: publicationGate) else { return }
        commitSnapshot(snapshot, preferredAnchor: anchor, chapterEnd: chapterEnd, animatedSync: animatedSync)
        prefetchAroundCurrentPage()
    }

    func flushDeferredSnapshotIfPossible() { publishPendingSnapshot(animatedSync: false) }

    var pagerViewportSizeForRendering: CGSize? {
        pagerViewport.measuredSize
    }
}
