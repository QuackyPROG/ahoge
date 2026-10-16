// Foundation geometry/anchor regression harness. No native renderer claims.
// Compile all Ahoge/Domain/**/*.swift plus Ahoge/Features/Reader/ReaderRenderModels.swift
// and this file into one temporary executable, then run it.
import Foundation

@main
struct ReaderRenderRegression {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
    static func rect(_ item: ReaderRenderItem) -> CGRect {
        switch item.fragment {
        case .full: return CGRect(x: 0, y: 0, width: 1, height: 1)
        case .spreadHalf(let half): return half.unitRect
        case .slice(_, _, let rect): return rect
        }
    }
    static func close(_ left: CGFloat, _ right: CGFloat) -> Bool { abs(left - right) < 0.000001 }
    static func main() {
        dualPageCases()
        interactionAndPublicationCases()
        adapterVisibilityAndViewportCases()
        progressEffectCases()
        let page = ReaderPage(id: "page", index: 0, title: "", body: "", accentHex: "", assetKind: .image, assetPath: nil, remoteURL: nil)
        let next = ReaderPage(id: "next", index: 1, title: "", body: "", accentHex: "", assetKind: .image, assetPath: nil, remoteURL: nil)
        let sizes = [page.id: CGSize(width: 12_000, height: 6_000), next.id: CGSize(width: 800, height: 1_200)]
        let paged = ReaderRenderData.build(pages: [page,next], mode: .verticalPaged, spreadBehavior: .fullPage, imageSizes: sizes)
        require(paged.logicalPages.count == 2 && paged.renderItems.map(\.sourcePageIndex) == [0,1], "Vertical pager keeps source order and full page identities")
        let split = ReaderRenderData.build(pages: [page,next], mode: .verticalPaged, spreadBehavior: .autoSplit, imageSizes: sizes)
        require(split.logicalPages.count == 3 && split.logicalPages.map(\.sourcePageIndex) == [0,0,1], "Wide halves keep the source page identity")
        let inverted = ReaderRenderData.build(pages: [page,next], mode: .verticalPaged, spreadBehavior: .autoSplit, imageSizes: sizes, invertSplitOrder: true)
        require(split.logicalPages[0].anchor.kind == "spread-left" && inverted.logicalPages[0].anchor.kind == "spread-right", "Split order reverses the actual halves")
        require(inverted.index(for: split.logicalPages[0].anchor) == 1, "Exact split anchor maps across inversion")
        require(paged.index(for: split.logicalPages[0].anchor) == 0, "Leaving split mode falls back to the same source page")
        let rtl = ReaderRenderData.build(pages: [page,next], mode: .pagerRTL, spreadBehavior: .fullPage, imageSizes: sizes)
        require(rtl.logicalPages.map(\.sourcePageIndex) == [0,1] && rtl.renderItems.map(\.sourcePageIndex) == [1,0], "RTL display order does not reverse persisted source identity")
        for mode in [ReaderMode.vertical, .webtoon] {
            let unrotated = ReaderRenderData.build(pages: [page,next], mode: mode, spreadBehavior: .fullPage, imageSizes: sizes)
            for clockwise in [true,false] {
                let rotated = ReaderRenderData.build(pages: [page,next], mode: mode, spreadBehavior: .fullPage, imageSizes: sizes, rotateWidePages: true, rotateClockwise: clockwise)
                require(rotated.logicalPages.map(\.anchor) == unrotated.logicalPages.map(\.anchor), "Rotation keeps continuous source anchors")
                let pieces = rotated.renderItems.filter { $0.sourcePageIndex == 0 }.map(rect)
                require(pieces.count > 1, "Enormous rotated wide pages must stay progressively sliced")
                require(pieces.allSatisfy { close($0.minY,0) && close($0.height,1) && $0.width > 0 }, "Rotated strips partition source X without changing source Y")
                let ordered = pieces.sorted { $0.minX < $1.minX }
                require(close(ordered[0].minX,0) && close(ordered.last!.maxX,1), "Rotated slices cover both source edges")
                for index in 1..<ordered.count { require(close(ordered[index - 1].maxX,ordered[index].minX), "No source gap or overlap between rotated slices") }
                require(clockwise ? pieces[0].minX < pieces.last!.minX : pieces[0].minX > pieces.last!.minX, "Rotation direction controls source-X slice order")
                require(rotated.renderItems.filter { $0.sourcePageIndex == 1 }.count == 1, "Neighbor portrait page remains a single render item")
                require(rotated.index(for: unrotated.logicalPages[1].anchor) == 1, "Neighbor anchor remains stable when another page rotates")
            }
        }
        print("Reader render geometry regressions passed: vertical/RTL identities, split inversion/remapping, continuous rotation partition/order and neighbor anchors")
    }

    static func adapterVisibilityAndViewportCases() {
        let pages = (0..<3).map { ReaderPage(id: "adapter-\($0)", index: $0, title: "", body: "", accentHex: "", assetKind: .image, assetPath: nil, remoteURL: nil) }
        let sizes = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, CGSize(width: 600, height: 900)) })
        let viewport = CGSize(width: 1200, height: 800)
        for mode in [ReaderMode.pagerDefault, .pagerLTR, .pagerRTL, .verticalPaged, .vertical, .webtoon] {
            let data = ReaderRenderData.build(pages: pages, mode: mode, spreadBehavior: .fullPage, imageSizes: sizes)
            let groups = ReaderDisplayGroup.build(data: data, mode: mode, sizes: sizes, policy: .always, firstPageAlone: false, viewport: viewport)
            let members = data.renderItems.map(\.id)
            let paged = Set(groups[0].members.map(\.id))
            let frames = [members[0]: CGRect(x: 50, y: -100, width: 1100, height: 450),
                          members[1]: CGRect(x: 50, y: 350, width: 1100, height: 450),
                          members[2]: CGRect(x: 50, y: 1000, width: 1100, height: 450),
                          "old-slice": CGRect(x: 0, y: 0, width: 1100, height: 450)]
            let continuous = mode == .vertical || mode == .webtoon
            let visible = ReaderSurfaceVisibility.visibleMembers(mode: mode, pagedMembers: paged,
                continuousMembers: Set(members), frames: frames, viewportSize: viewport)
            let scroll = ReaderSurfaceVisibility.continuousScrollMember
            require(visible == (continuous ? Set([members[0], members[1], scroll]) : paged), "Actual mode adapter chooses intersecting render IDs or pager members")
            require(!visible.contains("old-slice"), "Old graph/slice frame cannot register")
            let member = continuous ? members[0] : groups[0].members[0].id
            let epoch = UUID(), host = UUID()
            let identity = ReaderSurfaceIdentity(epoch: epoch, member: member, host: host, generation: 1)
            var owners = ReaderSurfaceOwnership()
            require(owners.receive(.register, from: identity, epoch: epoch, visible: visible), "Actual visible adapter member registers")
            func gate() -> ReaderPublicationGate { ReaderPublicationGate(surfaceOwned: owners.isOwned, pagerIdle: true, hasTransition: false, chapterTransitioning: false) }
            let original = ReaderContentSnapshot(chapterID: "adapter", mode: mode, pages: pages, imageSizes: sizes, renderData: data, displayGroups: groups)
            let changedMode: ReaderMode = continuous ? .pagerLTR : .webtoon
            let changedData = ReaderRenderData.build(pages: pages, mode: changedMode, spreadBehavior: .fullPage, imageSizes: sizes)
            let newest = ReaderContentSnapshot(chapterID: "adapter", mode: changedMode, pages: pages, imageSizes: sizes, renderData: changedData,
                displayGroups: ReaderDisplayGroup.build(data: changedData, mode: changedMode, sizes: sizes, policy: .always, firstPageAlone: false, viewport: viewport))
            let anchor = data.logicalPages[0].anchor
            for activity in [ReaderSurfaceActivity.pan, .pinch, .animatedZoom] {
                var pending = ReaderPendingPublication<ReaderContentSnapshot, ReaderLogicalAnchor>()
                _ = owners.receive(.begin(activity), from: identity, epoch: epoch, visible: visible)
                pending.request(original, chapter: "adapter", anchor: anchor)
                pending.request(newest, chapter: "adapter", anchor: nil)
                require(pending.take(chapter: "adapter", gate: gate()) == nil, "Mode/metadata requests defer in every actual adapter during pan/pinch/animated zoom")
                _ = owners.receive(.viewport, from: identity, epoch: epoch, visible: visible)
                require(owners.isOwned, "Layout and measurement do not release adapter ownership")
                _ = owners.receive(.end(activity), from: identity, epoch: epoch, visible: visible)
                let publication = pending.take(chapter: "adapter", gate: gate())
                require(publication?.0.mode == changedMode && publication?.1 == anchor && changedData.index(for: anchor) == 0, "Final terminal publishes newest mode once with source anchor")
                require(pending.take(chapter: "adapter", gate: gate()) == nil, "Repeated idle cannot publish twice")
            }
            let replacement = ReaderSurfaceIdentity(epoch: epoch, member: member, host: host, generation: 2)
            _ = owners.receive(.register, from: replacement, epoch: epoch, visible: visible)
            _ = owners.receive(.begin(.pinch), from: replacement, epoch: epoch, visible: visible)
            require(!owners.receive(.retire, from: identity, epoch: epoch, visible: visible) && owners.isOwned, "Old adapter generation cannot release replacement")
            require(!owners.receive(.begin(.pan), from: replacement, epoch: UUID(), visible: visible), "Old adapter epoch rejected")
            _ = owners.receive(.retire, from: replacement, epoch: epoch, visible: visible)
            require(!owners.isOwned && !owners.receive(.begin(.pan), from: replacement, epoch: epoch, visible: visible), "Disappearance retires exact adapter and forbids resurrection")
            if continuous {
                let outer = ReaderSurfaceIdentity(epoch: epoch, member: scroll, host: UUID(), generation: 0)
                let other = ReaderSurfaceIdentity(epoch: epoch, member: members[1], host: UUID(), generation: 1)
                _ = owners.receive(.register, from: outer, epoch: epoch, visible: visible)
                _ = owners.receive(.register, from: other, epoch: epoch, visible: visible)
                _ = owners.receive(.begin(.pinch), from: other, epoch: epoch, visible: visible)
                var pending = ReaderPendingPublication<ReaderContentSnapshot, ReaderLogicalAnchor>()
                pending.request(newest, chapter: "adapter", anchor: anchor)
                for phase in [ReaderContinuousScrollPhase.tracking, .interacting, .decelerating, .animating] {
                    _ = owners.receive(phase.event, from: outer, epoch: epoch, visible: visible)
                    require(pending.take(chapter: "adapter", gate: gate()) == nil, "Outer fit-scale tracking/drag/deceleration/scroll animation independently defers mode update")
                }
                _ = owners.receive(ReaderContinuousScrollPhase.idle.event, from: outer, epoch: epoch, visible: visible)
                require(owners.isOwned, "Outer idle retains inner pinch")
                // Native preference updates use this same mode/geometry policy. No
                // frames means transition-only view; container may still be live.
                let departed = ReaderSurfaceVisibility.visibleMembers(mode: mode, pagedMembers: paged,
                    continuousMembers: Set(members), frames: [:], viewportSize: viewport)
                owners.reconcile(visible: departed)
                require(!owners.isOwned && owners.registrations[scroll] == outer, "Scroll departure retires inner owner while retaining container registration")
                require(!owners.receive(.begin(.pan), from: other, epoch: epoch, visible: departed), "Offscreen inner callback cannot reacquire")
                require(pending.take(chapter: "adapter", gate: gate())?.0.mode == changedMode, "Visibility retirement retries pending mode publication")
                _ = owners.receive(ReaderContinuousScrollPhase.decelerating.event, from: outer, epoch: epoch, visible: departed)
                _ = owners.receive(.retire, from: outer, epoch: epoch, visible: departed)
                require(!owners.isOwned && !owners.receive(ReaderContinuousScrollPhase.interacting.event, from: outer, epoch: epoch, visible: departed), "Container disappearance/cancellation retires and rejects old phase callbacks")
                require(!owners.receive(.register, from: outer, epoch: UUID(), visible: departed), "Chapter/request/mode epoch excludes old scroll mount")
            }
        }
        let data = ReaderRenderData.build(pages: Array(pages.prefix(2)), mode: .pagerLTR, spreadBehavior: .fullPage, imageSizes: sizes)
        let invalid = [CGSize.zero, CGSize(width: 1200, height: 0), CGSize(width: 0, height: 800),
            CGSize(width: 1200, height: -1), CGSize(width: -1, height: 800),
            CGSize(width: CGFloat.nan, height: 800), CGSize(width: 1200, height: CGFloat.nan),
            CGSize(width: CGFloat.infinity, height: 800), CGSize(width: 1200, height: CGFloat.infinity)]
        for raw in invalid {
            let measurement = ReaderViewportMeasurement(raw)
            require(measurement.measuredSize == nil, "Adapter never converts invalid usable viewport into measurement")
            require(measurement.layoutSize.width.isFinite && measurement.layoutSize.height.isFinite && measurement.layoutSize.width >= 1 && measurement.layoutSize.height >= 1, "Invalid dimensions retain safe finite layout")
            require(ReaderDisplayGroup.build(data: data, mode: .pagerLTR, sizes: sizes, policy: .wide, firstPageAlone: false, viewport: measurement.measuredSize).count == 2, "Actual normalization boundary preserves wide singleton fallback")
        }
        var measurement = ReaderViewportMeasurement(.zero)
        for raw in [viewport, CGSize(width: 1200, height: 0), CGSize(width: 800, height: 1200), CGSize(width: 900, height: 900), viewport] {
            let previous = measurement
            measurement = ReaderViewportMeasurement(raw)
            require(previous != measurement, "Startup/resize/recovery changes are observable by actual View normalization")
            let count = ReaderDisplayGroup.build(data: data, mode: .pagerLTR, sizes: sizes, policy: .wide, firstPageAlone: false, viewport: measurement.measuredSize).count
            require(count == (raw == viewport ? 1 : 2), "Valid wide recovers after invalid/portrait/square geometry")
        }
        print("Production adapter visibility, lifecycle, pending mode and viewport-normalization fixtures passed")
    }

    static func interactionAndPublicationCases() {
        let epoch = UUID(), host = UUID()
        let left = ReaderSurfaceIdentity(epoch: epoch, member: "left", host: host, generation: 1)
        let right = ReaderSurfaceIdentity(epoch: epoch, member: "right", host: UUID(), generation: 1)
        let replacement = ReaderSurfaceIdentity(epoch: epoch, member: "left", host: host, generation: 2)
        let visible: Set<String> = ["left", "right"]
        var owners = ReaderSurfaceOwnership()
        func gate(pagerIdle: Bool = true, transition: Bool = false, chapter: Bool = false) -> ReaderPublicationGate {
            ReaderPublicationGate(surfaceOwned: owners.isOwned, pagerIdle: pagerIdle, hasTransition: transition, chapterTransitioning: chapter)
        }
        require(owners.receive(.register, from: left, epoch: epoch, visible: visible), "Live left registers")
        require(owners.receive(.register, from: right, epoch: epoch, visible: visible), "Live right registers")
        var pending = ReaderPendingPublication<Int, String>()
        _ = owners.receive(.begin(.pan), from: left, epoch: epoch, visible: visible)
        _ = owners.receive(.begin(.pinch), from: right, epoch: epoch, visible: visible)
        pending.request(1, chapter: "chapter", anchor: "source-right")
        pending.request(2, chapter: "chapter", anchor: nil)
        require(pending.take(chapter: "chapter", gate: gate()) == nil, "Either owner defers metadata and viewport requests")
        _ = owners.receive(.change(.pinch), from: right, epoch: epoch, visible: visible)
        _ = owners.receive(.end(.pinch), from: right, epoch: epoch, visible: visible)
        require(owners.isOwned, "Ending right pinch across scale one cannot release left pan")
        _ = owners.receive(.panEnded(decelerates: true), from: left, epoch: epoch, visible: visible)
        require(owners.isOwned && owners.activities["left"]?.active == [.deceleration], "Pan hands to deceleration without an idle gap")
        pending.request(3, chapter: "chapter", anchor: nil)
        _ = owners.receive(.end(.deceleration), from: left, epoch: epoch, visible: visible)
        for blocked in [gate(pagerIdle: false), gate(transition: true), gate(chapter: true)] {
            require(pending.take(chapter: "chapter", gate: blocked) == nil, "Each independent terminal gate prevents publication")
        }
        let published = pending.take(chapter: "chapter", gate: gate())
        require(published?.0 == 3 && published?.1 == "source-right", "Final terminal publishes newest snapshot once and retains explicit source intent")
        require(pending.take(chapter: "chapter", gate: gate()) == nil, "Repeated terminal has no duplicate commit/effects")
        pending.request(4, chapter: "chapter", anchor: "old-explicit")
        pending.focusChanged()
        pending.request(5, chapter: "chapter", anchor: nil)
        require(pending.take(chapter: "chapter", gate: gate())?.1 == nil, "Later user focus uses current source anchor at publication")
        pending.request(6, chapter: "chapter", anchor: "explicit")
        pending.request(7, chapter: "chapter", anchor: "new-explicit")
        require(pending.take(chapter: "chapter", gate: gate())?.1 == "new-explicit", "New explicit target wins")
        pending.request(8, chapter: "chapter", anchor: nil, chapterEnd: true)
        pending.request(9, chapter: "chapter", anchor: nil)
        require(pending.take(chapter: "chapter", gate: gate())?.2 == true, "Chapter end intent survives later metadata")
        pending.request(10, chapter: "old", anchor: "old-source")
        require(pending.take(chapter: "new", gate: gate()) == nil && pending.snapshot == nil, "Old chapter cannot publish into new chapter")
        for activity in [ReaderSurfaceActivity.pan, .pinch, .animatedZoom] {
            _ = owners.receive(.begin(activity), from: left, epoch: epoch, visible: visible)
            _ = owners.receive(.begin(.pinch), from: right, epoch: epoch, visible: visible)
            _ = owners.receive(.end(activity), from: left, epoch: epoch, visible: visible)
            require(owners.isOwned, "Cancel/fail/interrupted animation releases only matching activity")
            _ = owners.receive(.end(.pinch), from: right, epoch: epoch, visible: visible)
            require(!owners.isOwned, "Final terminal restores idle, including singleton scale one/below one")
        }
        _ = owners.receive(.begin(.pan), from: left, epoch: epoch, visible: visible)
        _ = owners.receive(.begin(.pinch), from: left, epoch: epoch, visible: visible)
        _ = owners.receive(.end(.pan), from: left, epoch: epoch, visible: visible)
        require(owners.isOwned, "Overlapping activities on same host remain independent")
        _ = owners.receive(.begin(.pan), from: right, epoch: epoch, visible: visible)
        _ = owners.receive(.register, from: replacement, epoch: epoch, visible: visible)
        require(owners.activities["left"]?.active.isEmpty == true && owners.isOwned, "Retry/config replacement retires left without clearing right")
        for stale in [ReaderSurfaceEvent.register, .begin(.pinch), .end(.pan), .retire] {
            require(!owners.receive(stale, from: left, epoch: epoch, visible: visible), "Old generation cannot register/begin/end/reset replacement")
        }
        _ = owners.receive(.begin(.pan), from: replacement, epoch: epoch, visible: visible)
        require(!owners.receive(.retire, from: left, epoch: epoch, visible: visible) && owners.isOwned, "Delayed old reset cannot release new owner")
        _ = owners.receive(.retire, from: replacement, epoch: epoch, visible: visible)
        require(owners.isOwned, "Failure/disappearance/dismantle retires exactly matching host")
        require(!owners.receive(.retire, from: replacement, epoch: epoch, visible: visible), "Repeated retirement harmless")
        owners.reconcile(visible: [])
        require(!owners.isOwned, "Departure removes last visible owner")
        require(!owners.receive(.begin(.pan), from: right, epoch: epoch, visible: []), "Offscreen retired callbacks cannot reacquire")
        let offscreen = ReaderSurfaceIdentity(epoch: epoch, member: "prefetch", host: UUID(), generation: 1)
        require(!owners.receive(.register, from: offscreen, epoch: epoch, visible: visible), "Prefetch surface cannot register visible ownership")
        require(!owners.receive(.register, from: replacement, epoch: UUID(), visible: visible), "Old session cannot register")
        let singleton = ReaderSurfaceIdentity(epoch: epoch, member: "single", host: UUID(), generation: 1)
        _ = owners.receive(.register, from: singleton, epoch: epoch, visible: ["single"])
        _ = owners.receive(.begin(.pinch), from: singleton, epoch: epoch, visible: ["single"])
        require(!gate().permitsPublication, "Singleton gesture also defers")
        _ = owners.receive(.end(.pinch), from: singleton, epoch: epoch, visible: ["single"])
        require(gate().permitsPublication, "Resting zoom is not transient publication ownership")
        require(!ReaderSurfaceNavigationPolicy(surfaceOwned: true, spread: false, scale: 1, edgeReady: true).permitsCapture, "Live surface wins even at armed edge")
        require(!ReaderSurfaceNavigationPolicy(surfaceOwned: false, spread: true, scale: 2, edgeReady: true).permitsCapture, "Resting zoom on either spread member blocks navigation")
        require(ReaderSurfaceNavigationPolicy(surfaceOwned: false, spread: false, scale: 2, edgeReady: true).permitsCapture, "Singleton resting zoom retains edge turns")
        require(!ReaderSurfaceNavigationPolicy(surfaceOwned: false, spread: false, scale: 2, edgeReady: false).permitsTap, "Resting zoom retains tap consumption")
        print("Production interaction/publication sequences passed")
    }

    static func progressEffectCases() {
        let pages = (0..<4).map { ReaderPage(id: "effect-\($0)", index: $0, title: "", body: "", accentHex: "", assetKind: .image, assetPath: nil, remoteURL: nil) }
        let sizes = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, CGSize(width: 800, height: 1200)) })
        let data = ReaderRenderData.build(pages: pages, mode: .pagerLTR, spreadBehavior: .fullPage, imageSizes: sizes)
        let groups = ReaderDisplayGroup.build(data: data, mode: .pagerLTR, sizes: sizes, policy: .always, firstPageAlone: false, viewport: nil)
        let snapshot = ReaderContentSnapshot(chapterID: "chapter", mode: .pagerLTR, pages: pages, imageSizes: sizes, renderData: data, displayGroups: groups)
        let selection = ReaderProgressPolicy.selection(snapshot: snapshot, chapterID: "chapter", focusedIndex: 2, visibleGroup: groups.last, visibilityCommitted: true)!
        let decision = ReaderProgressPolicy.decision(pageIndex: selection.focusedIndex, totalPages: selection.totalPages, previousChapterMatches: false, previousTotal: 99, wasRead: false, incognito: false, finalSourceVisible: selection.finalSourceVisible)
        require(decision.isRead && decision.pageIndex == 2 && decision.totalPages == 4 && decision.writesHistory, "Actual record/chapter/history outputs complete final spread while saving earlier focus")
        require(selection.focusedSourceID == pages[2].id, "Export uses same focused source policy")
        for committed in [false, true] {
            let nonfinal = ReaderProgressPolicy.selection(snapshot: snapshot, chapterID: "chapter", focusedIndex: 0, visibleGroup: groups.first, visibilityCommitted: committed)!
            require(!nonfinal.finalSourceVisible, "Nonfinal committed or pending visibility never completes")
        }
        require(ReaderProgressPolicy.selection(snapshot: snapshot, chapterID: "chapter", focusedIndex: 2, visibleGroup: groups.last, visibilityCommitted: false)?.finalSourceVisible == false, "Noncommitted/transition visibility rejected")
        require(ReaderProgressPolicy.selection(snapshot: snapshot, chapterID: "stale", focusedIndex: 2, visibleGroup: groups.last, visibilityCommitted: true) == nil, "Old chapter snapshot rejected")
        for invalid in [-1, 4, Int.max] {
            require(ReaderProgressPolicy.selection(snapshot: snapshot, chapterID: "chapter", focusedIndex: invalid, visibleGroup: groups.last, visibilityCommitted: true) == nil, "Invalid focus rejected before effects/export")
        }
        for input in [(0,0,false,0,false,false,false), (8,4,true,10,false,false,false), (-4,4,false,99,false,true,false), (0,1,false,0,false,false,false), (0,4,false,0,true,false,false)] {
            let d = ReaderProgressPolicy.decision(pageIndex: input.0, totalPages: input.1, previousChapterMatches: input.2, previousTotal: input.3, wasRead: input.4, incognito: input.5, finalSourceVisible: input.6)
            require(d.pageIndex >= 0 && d.pageIndex <= max(d.totalPages - 1,0), "Model output clamped")
            require(d.writesHistory == !input.5, "Incognito suppresses history only")
            if input.1 == 0 { require(!d.isRead, "Empty chapter cannot complete") }
            if input.2 { require(d.totalPages == 10 && d.pageIndex == 8 && !d.isRead, "Same chapter total floor prevents false completion") }
            if input.1 == 1 || input.4 { require(d.isRead, "One page and sticky prior read retained") }
        }
        let split = ReaderRenderData.build(pages: pages, mode: .pagerLTR, spreadBehavior: .autoSplit, imageSizes: Dictionary(uniqueKeysWithValues: pages.map { ($0.id, CGSize(width: 1600,height: 800)) }))
        let falseSpread = ReaderDisplayGroup(members: Array(split.renderItems.suffix(2)))
        let splitSnapshot = ReaderContentSnapshot(chapterID: "chapter", mode: .pagerLTR, pages: pages, imageSizes: [:], renderData: split, displayGroups: [falseSpread])
        require(ReaderProgressPolicy.selection(snapshot: splitSnapshot, chapterID: "chapter", focusedIndex: falseSpread.first.logicalPageIndex, visibleGroup: falseSpread, visibilityCommitted: true)?.finalSourceVisible == false, "Split halves cannot assert final-source override")
        let offscreenSnapshot = ReaderContentSnapshot(chapterID: "chapter", mode: .pagerLTR, pages: pages, imageSizes: sizes, renderData: data, displayGroups: [groups.first!])
        require(ReaderProgressPolicy.selection(snapshot: offscreenSnapshot, chapterID: "chapter", focusedIndex: 2, visibleGroup: groups.last, visibilityCommitted: true)?.finalSourceVisible == false, "Noncommitted group cannot assert final-source override")
        let emptyData = ReaderRenderData(logicalPages: [], renderItems: [])
        let empty = ReaderContentSnapshot(chapterID: "chapter", mode: .pagerLTR, pages: [], imageSizes: [:], renderData: emptyData)
        require(ReaderProgressPolicy.selection(snapshot: empty, chapterID: "chapter", focusedIndex: 0, visibleGroup: nil, visibilityCommitted: true) == nil, "Empty chapter has no progress/export selection")
        let normal = ReaderProgressPolicy.decision(pageIndex: 0, totalPages: 4, previousChapterMatches: false, previousTotal: 99, wasRead: false, incognito: false, finalSourceVisible: false)
        require(normal.totalPages == 4 && normal.pageIndex == 0 && !normal.isRead, "Different chapter cannot import prior page floor or read state")
        let slices = ReaderRenderData.build(pages: pages, mode: .webtoon, spreadBehavior: .fullPage, imageSizes: Dictionary(uniqueKeysWithValues: pages.map { ($0.id, CGSize(width: 800,height: 16000)) }))
        let sliceGroup = ReaderDisplayGroup(members: Array(slices.renderItems.suffix(2)))
        let sliceSnapshot = ReaderContentSnapshot(chapterID: "chapter", mode: .webtoon, pages: pages, imageSizes: [:], renderData: slices, displayGroups: [sliceGroup])
        require(ReaderProgressPolicy.selection(snapshot: sliceSnapshot, chapterID: "chapter", focusedIndex: 3, visibleGroup: sliceGroup, visibilityCommitted: true)?.finalSourceVisible == false, "Slices cannot assert final-source override")
        print("Production progress effect decisions passed")
    }

    static func dualPageCases() {
        let pages = (0..<7).map { ReaderPage(id: "dual-\($0)", index: $0, title: "", body: "", accentHex: "", assetKind: .image, assetPath: nil, remoteURL: nil) }
        let portrait = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, CGSize(width: 800, height: 1200)) })
        func groups(_ count: Int, mode: ReaderMode = .pagerLTR, policy: ReaderDualPageDisplay = .always,
                    cover: Bool = false, sizes: [String: CGSize]? = nil, viewport: CGSize? = nil,
                    split: ReaderSpreadBehavior = .fullPage) -> (ReaderRenderData, [ReaderDisplayGroup]) {
            let data = ReaderRenderData.build(pages: Array(pages.prefix(count)), mode: mode,
                spreadBehavior: split, imageSizes: sizes ?? portrait)
            return (data, ReaderDisplayGroup.build(data: data, mode: mode, sizes: sizes ?? portrait,
                policy: policy, firstPageAlone: cover, viewport: viewport))
        }
        for count in 0...7 {
            for cover in [false, true] {
                let (data, result) = groups(count, cover: cover)
                require(result.flatMap(\.members).map(\.logicalPageIndex) == Array(0..<count), "Pairing neither drops nor duplicates any logical/source page")
                require(result.count == (cover && count > 0 ? 1 + count / 2 : (count + 1) / 2), "Zero/one/odd/even cover grouping")
                for index in 0..<count {
                    let group = result.first { $0.contains(index) }!
                    require(group.members.contains { $0.page.id == data.logicalPages[index].anchor.sourcePageID }, "Both-member target lookup preserves focused source/export anchor")
                    require(data.index(for: data.anchor(for: index)!) == index, "Regrouping leaves focused resume/history anchor unchanged")
                }
            }
        }
        let (data, pair) = groups(2)
        require(pair[0].physicalMembers(rtl: false).map(\.sourcePageIndex) == [0,1], "LTR places earlier page left")
        require(pair[0].physicalMembers(rtl: true).map(\.sourcePageIndex) == [1,0], "RTL places earlier page right")
        require(pair[0].sourceRange == 0...1 && pair[0].reachesEnd(sourceCount: 2), "Final visible member completes while focused anchor may remain earlier")
        require(data.anchor(for: 0)!.sourcePageID == pages[0].id, "Completion never rewrites focused resume/export anchor")
        let (_, rtl) = groups(5, mode: .pagerRTL)
        require(rtl.map { $0.first.sourcePageIndex } == [4,2,0], "RTL group traversal preserves chapter reading order")
        for reverse in [false,true] {
            let items = ReaderPagerItem.build(groups: reverse ? rtl : groups(5).1, rtl: reverse)
            require(items.count == 5 && Set(items.map(\.id)).count == items.count, "Each chapter sentinel appears exactly once around groups")
            require(items[0].id == (reverse ? "transition-next" : "transition-previous") && items.last!.id == (reverse ? "transition-previous" : "transition-next"), "Sentinel direction follows physical pager order")
            for index in 0..<5 { require(items.filter { $0.contains(logicalIndex: index) }.count == 1, "Production navigation maps either source member into exactly one group") }
        }
        for policy in ReaderDualPageDisplay.allCases {
            for mode in [ReaderMode.verticalPaged, .vertical, .webtoon] {
                require(groups(2, mode: mode, policy: policy).1.allSatisfy { $0.members.count == 1 }, "Unsupported modes remain single")
            }
        }
        require(groups(2, policy: .never).1.count == 2, "Default never remains single")
        for viewport in [CGSize.zero, CGSize(width: 800,height: 1200), CGSize(width: 900,height: 900)] {
            require(groups(2, policy: .wide, viewport: viewport).1.count == 2, "Wide requires measured width greater than height")
        }
        require(groups(2, policy: .wide).1.count == 2 && groups(2, policy: .wide, viewport: CGSize(width: 1200,height: 800)).1.count == 1, "Unknown viewport fallback and wide landscape")
        for excluded in [CGSize(width: 1200,height: 800), CGSize(width: 800,height: 800), CGSize.zero] {
            var sizes = portrait; sizes[pages[1].id] = excluded
            let (_, result) = groups(3, sizes: sizes)
            require(result.count == 3, "Ineligible middle page never permits distant pairing")
        }
        var unknown = portrait; unknown[pages[1].id] = nil
        require(groups(3, sizes: unknown).1.count == 3, "Unknown dimensions stay single")
        var wide = portrait; wide[pages[1].id] = CGSize(width: 1600,height: 800)
        let (_, splitGroups) = groups(3, sizes: wide, split: .autoSplit)
        require(splitGroups.count == 4 && splitGroups.allSatisfy { $0.members.count == 1 }, "Split halves stay alone and prevent crossing")
        let slice = ReaderRenderItem(id: "slice", logicalPageID: data.logicalPages[0].id, logicalPageIndex: 0,
            sourcePageIndex: 0, page: pages[0], fragment: .slice(index: 0,total: 2,unitRect: CGRect(x: 0,y: 0,width: 1,height: 0.5)))
        let slicedData = ReaderRenderData(logicalPages: data.logicalPages, renderItems: [slice,data.renderItems[1]])
        require(ReaderDisplayGroup.build(data: slicedData, mode: .pagerLTR, sizes: portrait, policy: .always,
            firstPageAlone: false, viewport: nil).count == 2, "Generated slices never pair")
        print("Dual-page production geometry/anchor cases passed")
    }
}
