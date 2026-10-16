// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

//
//  ReaderView+ComputedState.swift
//  Ahoge
//

import SwiftUI

extension ReaderView {
    var liveResolvedPages: [ReaderPage] {
        let resolved = model.resolvedChapter(currentChapter)
        return resolved.pages.isEmpty ? currentChapter.pages : resolved.pages
    }

    var currentPages: [ReaderPage] {
        committedSnapshot?.pages ?? []
    }

    var activeReaderMode: ReaderMode {
        committedSnapshot?.mode ?? model.state.readerPreferences.mode
    }

    var isVerticalReader: Bool {
        activeReaderMode == .vertical || activeReaderMode == .webtoon
    }

    var isWebtoonMode: Bool {
        activeReaderMode == .webtoon
    }

    var isNavigationSuspended: Bool {
        isChapterTransitioning || pageLoadState == .loading
    }

    var transitionDirection: ReaderTransitionDirection? {
        transitionState?.direction
    }

    private var readerRenderData: ReaderRenderData {
        committedSnapshot?.renderData ?? ReaderRenderData(logicalPages: [], renderItems: [])
    }

    var logicalPages: [ReaderLogicalPage] {
        readerRenderData.logicalPages
    }

    var verticalRenderItems: [ReaderRenderItem] {
        readerRenderData.renderItems
    }

    private var pagerRenderItems: [ReaderDisplayGroup] {
        committedSnapshot?.displayGroups ?? []
    }

    var pagerItems: [ReaderPagerItem] {
        ReaderPagerItem.build(groups: pagerRenderItems, rtl: isRTLPager)
    }

    var currentPagerInteractionState: ReaderInteractionState {
        guard pagerItems.indices.contains(pagerDisplayIndex) else { return .default }
        guard case .render(let item) = pagerItems[pagerDisplayIndex] else { return .default }
        return item.members.compactMap { surfaceInteractionStates[$0.id] }
            .first(where: { $0.consumesTapNavigation }) ?? .default
    }

    var visibleDisplayGroup: ReaderDisplayGroup? {
        guard pagerItems.indices.contains(pagerDisplayIndex),
              case .render(let group) = pagerItems[pagerDisplayIndex] else { return nil }
        return group
    }

    var visibleSurfaceIDs: Set<String> {
        ReaderSurfaceVisibility.visibleMembers(mode: activeReaderMode,
            pagedMembers: Set(visibleDisplayGroup?.members.map(\.id) ?? []),
            continuousMembers: Set(verticalRenderItems.map(\.id)), frames: continuousFrames,
            viewportSize: continuousViewportSize)
    }

    var surfaceInteractionOwned: Bool { surfaceOwnership.isOwned }

    var publicationGate: ReaderPublicationGate {
        ReaderPublicationGate(surfaceOwned: surfaceInteractionOwned, pagerIdle: readerInteractionPhase == .idle,
            hasTransition: transitionState != nil, chapterTransitioning: isChapterTransitioning)
    }

    var currentPagerTransitionDirection: ReaderTransitionDirection? {
        guard !isVerticalReader else { return nil }
        guard pagerItems.indices.contains(pagerDisplayIndex) else { return nil }
        switch pagerItems[pagerDisplayIndex] {
        case .previousChapter:
            return .previous
        case .nextChapter:
            return .next
        case .render:
            return nil
        }
    }

    var isRTLPager: Bool {
        switch activeReaderMode {
        case .pagerDefault, .pagerRTL:
            return true
        case .pagerLTR, .vertical, .webtoon, .verticalPaged:
            return false
        }
    }
}
