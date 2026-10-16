// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

//
//  ReaderView+PageStateUpdates.swift
//  Ahoge
//

import SwiftUI

extension ReaderView {
    func updatePagerViewportSize(_ size: CGSize) {
        let measurement = ReaderViewportMeasurement(size)
        let didChange = pagerViewport != measurement
        pagerViewport = measurement
        guard didChange, !isVerticalReader, !currentPages.isEmpty else { return }
        refreshCommittedSnapshot(preferredPageIndex: nil, animatedSync: false)
    }

    func registerImageSize(_ size: CGSize, for pageID: String) {
        guard size.width > 0, size.height > 0 else { return }
        let rounded = CGSize(width: size.width.rounded(.toNearestOrAwayFromZero), height: size.height.rounded(.toNearestOrAwayFromZero))
        if let existing = pageImageSizes[pageID], existing == rounded {
            return
        }

        var updatedSizes = pageImageSizes
        updatedSizes[pageID] = rounded
        pageImageSizes = updatedSizes
        refreshCommittedSnapshot(preferredPageIndex: deferredResumePageIndex, animatedSync: false)
    }

    func updateSurfaceInteractionState(_ state: ReaderInteractionState, for itemID: String) {
        guard let identity = state.identity, identity.member == itemID,
              surfaceOwnership.receive(state.event, from: identity, epoch: interactionEpoch, visible: visibleSurfaceIDs) else { return }
        if state.event == .retire { surfaceInteractionStates[itemID] = nil }
        else { surfaceInteractionStates[itemID] = state }
        flushDeferredSnapshotIfPossible()
    }

    func reconcileSurfaceInteractions() {
        surfaceOwnership.reconcile(visible: visibleSurfaceIDs)
        surfaceInteractionStates = surfaceInteractionStates.filter { visibleSurfaceIDs.contains($0.key) }
    }

    func registerPageLuminance(_ luminance: CGFloat, for itemID: String) {
        let bounded = min(max(luminance, 0), 1)
        if pageLuminanceByRenderItemID[itemID] == bounded {
            return
        }
        pageLuminanceByRenderItemID[itemID] = bounded
    }
}
