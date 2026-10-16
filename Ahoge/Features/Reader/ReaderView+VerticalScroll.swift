// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

//
//  ReaderView+VerticalScroll.swift
//  Ahoge
//

import SwiftUI

extension ReaderView {
    func pageAnchorID(for index: Int) -> String {
        "\(retryTick)-\(currentChapter.id)-\(index)"
    }

    func scrollToCurrentPage(using proxy: ScrollViewProxy, animated: Bool) {
        guard isVerticalReader, pageLoadState == .loaded, !verticalRenderItems.isEmpty else { return }
        guard let firstRenderIndex = verticalRenderItems.firstIndex(where: { $0.logicalPageIndex == boundedPageIndex(for: pageIndex) }) else {
            return
        }
        let action = {
            proxy.scrollTo(pageAnchorID(for: firstRenderIndex), anchor: .top)
        }
        if animated && shouldAnimatePages {
            withAnimation(.easeInOut(duration: 0.2), action)
        } else {
            action()
        }
    }

    func updateVerticalPageIndex(from memberFrames: [String: CGRect], viewportSize: CGSize, epoch: UUID) {
        guard epoch == interactionEpoch, isVerticalReader else { return }
        continuousFrames = memberFrames
        continuousViewportSize = viewportSize
        // Reconcile even during slider movement or with no visible page. Retire
        // departed owners before retrying the same pending-publication gate.
        reconcileSurfaceInteractions()
        flushDeferredSnapshotIfPossible()
        guard epoch == interactionEpoch, isVerticalReader else { return }
        guard let measuredSize = ReaderViewportMeasurement(viewportSize).measuredSize else { return }
        let frames = Dictionary(uniqueKeysWithValues: verticalRenderItems.enumerated().compactMap { offset, item in
            memberFrames[item.id].map { (offset, $0) }
        })
        let viewportHeight = measuredSize.height
        guard isVerticalReader, pageLoadState == .loaded, !frames.isEmpty else { return }
        guard sliderActiveValue == nil else { return }
        
        let visibleFrames = frames.filter { offset, _ in
            visibleSurfaceIDs.contains(verticalRenderItems[offset].id)
        }

        if visibleFrames.isEmpty {
            // When the transition page is fully in view, reader render items can be out of viewport.
            // Pin pageIndex to the nearest boundary so drag-to-transition remains responsive.
            if let lastOffset = frames.keys.max(),
               let lastFrame = frames[lastOffset],
               lastFrame.maxY <= 1,
               let lastLogicalPage = verticalRenderItems.last?.logicalPageIndex {
                let boundedLast = boundedPageIndex(for: lastLogicalPage)
                if boundedLast != pageIndex {
                    pageIndex = boundedLast
                }
                return
            }

            if let firstOffset = frames.keys.min(),
               let firstFrame = frames[firstOffset],
               firstFrame.minY >= viewportHeight - 1,
               pageIndex != 0 {
                pageIndex = 0
            }
            return
        }

        // Safely pin to bottom if the final render item sits slightly above the lower edge.
        let sortedVisible = visibleFrames.sorted { $0.key < $1.key }
        if let last = sortedVisible.last,
           last.key == verticalRenderItems.indices.last,
           last.value.maxY <= viewportHeight + 5 {
            let logicalIndex = boundedPageIndex(for: verticalRenderItems[last.key].logicalPageIndex)
            if logicalIndex != pageIndex {
                pageIndex = logicalIndex
            }
            return
        }

        let selectedIndex: Int?
        if let coveringTop = visibleFrames
            .filter({ _, frame in frame.minY <= 1 && frame.maxY > 1 })
            .min(by: { lhs, rhs in lhs.key < rhs.key }) {
            selectedIndex = coveringTop.key
        } else {
            selectedIndex = visibleFrames.min(by: { lhs, rhs in
                if lhs.value.minY == rhs.value.minY {
                    return lhs.key < rhs.key
                }
                return lhs.value.minY < rhs.value.minY
            })?.key
        }

        guard let selectedIndex else { return }
        guard verticalRenderItems.indices.contains(selectedIndex) else { return }
        let logicalIndex = boundedPageIndex(for: verticalRenderItems[selectedIndex].logicalPageIndex)
        if logicalIndex != pageIndex {
            pageIndex = logicalIndex
        }
    }
}
