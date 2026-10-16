// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

//
//  ReaderTiledPageView.swift
//  Ahoge
//

import CoreImage
import SwiftUI
import UIKit

struct ReaderImageAssetSource: Equatable, Hashable {
    let cacheKey: String
    let remoteURL: URL?
    let localFileURL: URL?
}

struct ReaderPageViewportState: Equatable {
    let identity: ReaderSurfaceIdentity
    let event: ReaderSurfaceEvent
    let scale: CGFloat
    let contentOffset: CGPoint
    let isLeftEdgeReadyForPageTurn: Bool
    let isRightEdgeReadyForPageTurn: Bool
}

struct ReaderColorTransform: Equatable, Hashable {
    let enabled: Bool
    let grayscale: Double
    let dimming: Double

    init(filter: ReaderColorFilter) {
        enabled = filter.enabled
        grayscale = filter.grayscale
        dimming = filter.dimming
    }

    var cacheKey: String {
        guard enabled else { return "off" }
        return "g\(Int((grayscale * 100).rounded()))-d\(Int((dimming * 100).rounded()))"
    }
}

struct ReaderPreviewImageResult {
    let image: UIImage
    let sourcePixelSize: CGSize
}

struct ReaderTileCacheKey: Hashable {
    let sourceKey: String
    let cropRect: CGRect
    let targetPixelSize: CGSize
    let transformKey: String
}

struct ReaderTileRequest: Hashable {
    let source: ReaderImageAssetSource
    let normalizedCropRect: CGRect
    let targetPixelSize: CGSize
    let colorTransform: ReaderColorTransform

    var cacheKey: ReaderTileCacheKey {
        ReaderTileCacheKey(
            sourceKey: source.cacheKey,
            cropRect: normalizedCropRect,
            targetPixelSize: targetPixelSize,
            transformKey: colorTransform.cacheKey
        )
    }
}

enum ReaderPageSizingMode: Equatable {
    case aspectFit
    case fitWidth
    case fitHeight
    case original
    case smartFit
    init(_ scale: ReaderScale) {
        switch scale {
        case .fitScreen: self = .aspectFit
        case .fitWidth: self = .fitWidth
        case .fitHeight: self = .fitHeight
        case .original: self = .original
        case .smartFit: self = .smartFit
        }
    }
}

struct ReaderTiledPageSurface: UIViewRepresentable {
    let imagePipeline: ReaderImagePipelining
    let source: ReaderImageAssetSource
    let variantKey: String
    let normalizedCropRect: CGRect
    let colorTransform: ReaderColorTransform
    let allowsZoom: Bool
    let allowsDetailTiles: Bool
    let sizingMode: ReaderPageSizingMode
    let zoomStart: ReaderZoomStart
    let cropBorders: Bool
    let doubleTapZoom: Bool
    let allowZoomOut: Bool
    let animateZoom: Bool
    let retryToken: Int
    let epoch: UUID
    let memberID: String
    let isVisible: Bool
    let onSourceSizeResolved: (CGSize) -> Void
    let onDisplayAspectRatioResolved: (CGFloat) -> Void
    let onPreviewLuminanceResolved: (CGFloat) -> Void
    let onViewportStateChanged: (ReaderPageViewportState) -> Void
    let onFailureChanged: (String?) -> Void

    static func dismantleUIView(_ uiView: ReaderTiledPageHostView, coordinator: ()) {
        uiView.cancelLoading()
    }

    func makeUIView(context: Context) -> ReaderTiledPageHostView {
        let view = ReaderTiledPageHostView()
        view.imagePipeline = imagePipeline
        view.onSourceSizeResolved = onSourceSizeResolved
        view.onDisplayAspectRatioResolved = onDisplayAspectRatioResolved
        view.onPreviewLuminanceResolved = onPreviewLuminanceResolved
        view.onViewportStateChanged = onViewportStateChanged
        view.onFailureChanged = onFailureChanged
        view.apply(
            configuration: .init(
                source: source,
                variantKey: variantKey,
                normalizedCropRect: normalizedCropRect,
                colorTransform: colorTransform,
                allowsZoom: allowsZoom,
                allowsDetailTiles: allowsDetailTiles,
                sizingMode: sizingMode,
                zoomStart: zoomStart,
                cropBorders: cropBorders,
                doubleTapZoom: doubleTapZoom,
                allowZoomOut: allowZoomOut,
                animateZoom: animateZoom,
                retryToken: retryToken, epoch: epoch, memberID: memberID, isVisible: isVisible
            )
        )
        return view
    }

    func updateUIView(_ uiView: ReaderTiledPageHostView, context: Context) {
        uiView.imagePipeline = imagePipeline
        uiView.onSourceSizeResolved = onSourceSizeResolved
        uiView.onDisplayAspectRatioResolved = onDisplayAspectRatioResolved
        uiView.onPreviewLuminanceResolved = onPreviewLuminanceResolved
        uiView.onViewportStateChanged = onViewportStateChanged
        uiView.onFailureChanged = onFailureChanged
        uiView.apply(
            configuration: .init(
                source: source,
                variantKey: variantKey,
                normalizedCropRect: normalizedCropRect,
                colorTransform: colorTransform,
                allowsZoom: allowsZoom,
                allowsDetailTiles: allowsDetailTiles,
                sizingMode: sizingMode,
                zoomStart: zoomStart,
                cropBorders: cropBorders,
                doubleTapZoom: doubleTapZoom,
                allowZoomOut: allowZoomOut,
                animateZoom: animateZoom,
                retryToken: retryToken, epoch: epoch, memberID: memberID, isVisible: isVisible
            )
        )
    }
}

@MainActor
final class ReaderTiledPageHostView: UIView, UIScrollViewDelegate {
    struct Configuration: Equatable {
        let source: ReaderImageAssetSource
        let variantKey: String
        let normalizedCropRect: CGRect
        let colorTransform: ReaderColorTransform
        let allowsZoom: Bool
        let allowsDetailTiles: Bool
        let sizingMode: ReaderPageSizingMode
        let zoomStart: ReaderZoomStart
        let cropBorders: Bool
        let doubleTapZoom: Bool
        let allowZoomOut: Bool
        let animateZoom: Bool
        let retryToken: Int
        let epoch: UUID
        let memberID: String
        let isVisible: Bool
    }

    var onSourceSizeResolved: ((CGSize) -> Void)?
    var onDisplayAspectRatioResolved: ((CGFloat) -> Void)?
    var onPreviewLuminanceResolved: ((CGFloat) -> Void)?
    var onViewportStateChanged: ((ReaderPageViewportState) -> Void)?
    var onFailureChanged: ((String?) -> Void)?
    var imagePipeline: ReaderImagePipelining = ReaderImagePipeline.shared

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let previewImageView = UIImageView()
    private let tileOverlayView = UIView()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private lazy var doubleTapGestureRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        recognizer.numberOfTapsRequired = 2
        recognizer.cancelsTouchesInView = true
        return recognizer
    }()

    private var configuration: Configuration?
    private var previewTask: Task<Void, Never>?
    private var tileTasks: [ReaderTileCacheKey: Task<Void, Never>] = [:]
    private var tileViews: [ReaderTileCacheKey: UIImageView] = [:]
    private var effectiveCropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    private var needsInitialPosition = true
    private var croppedSourcePixelSize: CGSize = .zero
    private var currentGeneration = UUID()
    private let mountedHost = UUID()
    private var surfaceGeneration = 0
    private var surfaceIdentity: ReaderSurfaceIdentity?
    private var panIdentity: ReaderSurfaceIdentity?
    private var pinchIdentity: ReaderSurfaceIdentity?
    private var animatedZoomIdentity: ReaderSurfaceIdentity?
    private var animatedZoomID: UUID?
    private var zoomAnimator: UIViewPropertyAnimator?

    private func cancelAnimatedZoom(release: Bool = true) {
        let identity = animatedZoomIdentity
        animatedZoomIdentity = nil
        animatedZoomID = nil
        zoomAnimator?.stopAnimation(true)
        zoomAnimator = nil
        if release, let identity { publishViewportState(event: .end(.animatedZoom), identity: identity) }
    }

    private func retireInteraction() {
        if let identity = surfaceIdentity { publishViewportState(event: .retire, identity: identity) }
        surfaceIdentity = nil
        panIdentity = nil
        pinchIdentity = nil
        cancelAnimatedZoom(release: false)
        scrollView.setZoomScale(scrollView.zoomScale, animated: false)
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
    }

    private func registerInteraction() {
        guard let configuration, configuration.isVisible else { return }
        surfaceGeneration += 1
        let identity = ReaderSurfaceIdentity(epoch: configuration.epoch, member: configuration.memberID,
            host: mountedHost, generation: surfaceGeneration)
        surfaceIdentity = identity
        publishViewportState(event: .register, identity: identity)
    }

    private var didArmLeftPageTurn = false
    private var didArmRightPageTurn = false
    private let tileLength: CGFloat = 256

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        previewTask?.cancel()
        tileTasks.values.forEach { $0.cancel() }
    }

    func cancelLoading() {
        retireInteraction()
        currentGeneration = UUID()
        previewTask?.cancel()
        previewTask = nil
        removeAllTiles()
    }

    func apply(configuration: Configuration) {
        let needsFullReload = self.configuration?.source != configuration.source
            || self.configuration?.variantKey != configuration.variantKey
            || self.configuration?.normalizedCropRect != configuration.normalizedCropRect
            || self.configuration?.colorTransform != configuration.colorTransform
            || self.configuration?.allowsZoom != configuration.allowsZoom
            || self.configuration?.allowsDetailTiles != configuration.allowsDetailTiles
            || self.configuration?.sizingMode != configuration.sizingMode
            || self.configuration?.zoomStart != configuration.zoomStart
            || self.configuration?.cropBorders != configuration.cropBorders
            || self.configuration?.allowZoomOut != configuration.allowZoomOut
            || self.configuration?.retryToken != configuration.retryToken

        let visibilityChanged = self.configuration?.epoch != configuration.epoch
            || self.configuration?.memberID != configuration.memberID
            || self.configuration?.isVisible != configuration.isVisible
        if visibilityChanged { retireInteraction() }
        doubleTapGestureRecognizer.isEnabled = configuration.doubleTapZoom
        self.configuration = configuration
        if needsFullReload {
            reload()
        } else {
            if visibilityChanged { registerInteraction() }
            configureZoom()
            layoutContentIfPossible()
            publishViewportState()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        loadingIndicator.center = CGPoint(x: bounds.midX, y: bounds.midY)
        if configuration != nil, bounds.width > 0, bounds.height > 0, previewImageView.image == nil, previewTask == nil {
            reload()
        }
        layoutContentIfPossible()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        configuration?.allowsZoom == true ? contentView : nil
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContentIfNeeded()
        updatePanBehavior()
        updateVisibleTiles()
        publishViewportState()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if !canTurnPagesFromHorizontalEdges {
            didArmLeftPageTurn = false
            didArmRightPageTurn = false
        }
        updateVisibleTiles()
        publishViewportState()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if let identity = panIdentity {
            publishViewportState(event: .panEnded(decelerates: decelerate), identity: identity)
            if !decelerate { panIdentity = nil }
        }
        armEdgeTurnIfNeeded()
        publishViewportState()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if let identity = panIdentity { publishViewportState(event: .end(.deceleration), identity: identity) }
        panIdentity = nil
        armEdgeTurnIfNeeded()
        publishViewportState()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        beginPan()
    }

    private func beginPan() {
        guard let identity = surfaceIdentity else { return }
        let priorPan = panIdentity
        panIdentity = identity
        publishViewportState(event: .begin(.pan), identity: identity)
        cancelAnimatedZoom()
        if let priorPan { publishViewportState(event: .end(.deceleration), identity: priorPan) }
    }

    @objc private func observePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began: beginPan()
        case .changed:
            if let identity = panIdentity { publishViewportState(event: .change(.pan), identity: identity) }
        case .cancelled, .failed:
            if let identity = panIdentity { publishViewportState(event: .end(.pan), identity: identity) }
            panIdentity = nil
        default: break // Delegate terminal supplies willDecelerate atomically.
        }
    }

    @objc private func observePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            guard let identity = surfaceIdentity else { return }
            pinchIdentity = identity
            publishViewportState(event: .begin(.pinch), identity: identity)
            cancelAnimatedZoom()
        case .changed:
            if let identity = pinchIdentity { publishViewportState(event: .change(.pinch), identity: identity) }
        case .ended, .cancelled, .failed:
            if let identity = pinchIdentity { publishViewportState(event: .end(.pinch), identity: identity) }
            pinchIdentity = nil
        default: break
        }
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        // Pinch terminal is observed on its recognizer. Programmatic zoom uses
        // the animator completion carrying the originating animation identity.
        publishViewportState()
    }

    private func setup() {
        backgroundColor = .clear

        scrollView.delegate = self
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(observePan(_:)))
        scrollView.pinchGestureRecognizer?.addTarget(self, action: #selector(observePinch(_:)))
        scrollView.backgroundColor = .clear
        scrollView.isDirectionalLockEnabled = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.bounces = true
        scrollView.addGestureRecognizer(doubleTapGestureRecognizer)
        addSubview(scrollView)

        contentView.backgroundColor = .clear
        scrollView.addSubview(contentView)

        previewImageView.backgroundColor = .clear
        previewImageView.contentMode = .scaleToFill
        previewImageView.clipsToBounds = true
        contentView.addSubview(previewImageView)

        tileOverlayView.backgroundColor = .clear
        contentView.addSubview(tileOverlayView)

        loadingIndicator.hidesWhenStopped = true
        addSubview(loadingIndicator)
    }

    private func reload() {
        retireInteraction()
        registerInteraction()
        previewTask?.cancel()
        previewTask = nil
        tileTasks.values.forEach { $0.cancel() }
        tileTasks.removeAll()
        tileViews.values.forEach { $0.removeFromSuperview() }
        tileViews.removeAll()
        previewImageView.image = nil
        croppedSourcePixelSize = .zero
        needsInitialPosition = true
        didArmLeftPageTurn = false
        didArmRightPageTurn = false
        currentGeneration = UUID()
        configureZoom()
        onFailureChanged?(nil)
        loadingIndicator.startAnimating()

        guard let configuration else { return }
        guard bounds.width > 0, bounds.height > 0 else { return }
        let generation = currentGeneration
        effectiveCropRect = configuration.normalizedCropRect
        let croppedAspectRatio = max(
            croppedSourcePixelSize.width > 0 && croppedSourcePixelSize.height > 0
                ? croppedSourcePixelSize.width / croppedSourcePixelSize.height
                : effectiveCropRect.width / max(effectiveCropRect.height, 0.01),
            0.01
        )
        let fittedPreviewSize = CGSize(width: bounds.width, height: bounds.width / croppedAspectRatio)
            .aspectFit(in: bounds.size)
        let maxPreviewPixels = max(fittedPreviewSize.width, fittedPreviewSize.height, 1) * traitCollection.displayScale * 3
        previewTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let full = CGRect(x: 0, y: 0, width: 1, height: 1)
                let border = configuration.cropBorders ? ((try? await self.imagePipeline.borderCrop(for: configuration.source)) ?? full) : full
                guard !Task.isCancelled, self.currentGeneration == generation else { return }
                self.effectiveCropRect = configuration.normalizedCropRect.intersection(border)
                if self.effectiveCropRect.isNull || self.effectiveCropRect.isEmpty { self.effectiveCropRect = configuration.normalizedCropRect }
                let preview = try await self.imagePipeline.previewImage(
                    for: configuration.source,
                    variantKey: configuration.variantKey,
                    normalizedCropRect: self.effectiveCropRect,
                    maxPixelSize: maxPreviewPixels,
                    colorTransform: configuration.colorTransform,
                    forceRefresh: configuration.retryToken > 0
                )
                guard self.currentGeneration == generation else { return }
                self.previewImageView.image = preview.image
                self.croppedSourcePixelSize = preview.sourcePixelSize.applyingCrop(self.effectiveCropRect)
                self.loadingIndicator.stopAnimating()
                self.onFailureChanged?(nil)
                self.onSourceSizeResolved?(preview.sourcePixelSize)
                self.onDisplayAspectRatioResolved?(self.croppedSourcePixelSize.width / max(self.croppedSourcePixelSize.height, 1))
                self.onPreviewLuminanceResolved?(self.estimateLuminance(for: preview.image))
                self.layoutContentIfPossible()
                self.publishViewportState()
                self.updateVisibleTiles()
            } catch {
                guard self.currentGeneration == generation else { return }
                self.loadingIndicator.stopAnimating()
                self.retireInteraction()
                self.onFailureChanged?("Tap retry to request the page again.")
            }
        }
    }

    private func configureZoom() {
        scrollView.minimumZoomScale = configuration?.allowZoomOut == true ? 0.5 : 1
        scrollView.maximumZoomScale = configuration?.allowsZoom == true ? 4 : 1
        if scrollView.zoomScale < scrollView.minimumZoomScale || scrollView.zoomScale > scrollView.maximumZoomScale {
            scrollView.zoomScale = scrollView.minimumZoomScale
        }
        updatePanBehavior()
    }

    private func layoutContentIfPossible() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard let previewImage = previewImageView.image else { return }
        guard let configuration else { return }

        let contentSize: CGSize
        switch configuration.sizingMode {
        case .aspectFit:
            let fitted = previewImage.size.aspectFit(in: bounds.size)
            contentSize = CGSize(width: max(fitted.width, 1), height: max(fitted.height, 1))
        case .fitWidth:
            let aspectRatio = max(previewImage.size.width / max(previewImage.size.height, 0.01), 0.01)
            let fittedHeight = max(bounds.width / aspectRatio, 1)
            contentSize = CGSize(width: max(bounds.width, 1), height: fittedHeight)
        case .fitHeight:
            let aspect = max(previewImage.size.width / max(previewImage.size.height, 1), 0.01)
            contentSize = CGSize(width: bounds.height * aspect, height: bounds.height)
        case .smartFit:
            let aspect = max(previewImage.size.width / max(previewImage.size.height, 1), 0.01)
            if aspect < bounds.width / bounds.height {
                contentSize = CGSize(width: bounds.width, height: bounds.width / aspect)
            } else { contentSize = CGSize(width: bounds.height * aspect, height: bounds.height) }
        case .original:
            // Source pixels converted to display points; limit enormous strips to a bounded scroll canvas.
            let native = CGSize(width: croppedSourcePixelSize.width / max(traitCollection.displayScale, 1), height: croppedSourcePixelSize.height / max(traitCollection.displayScale, 1))
            let limit = max(bounds.width, bounds.height) * 16
            let ratio = min(1, limit / max(native.width, native.height, 1))
            contentSize = CGSize(width: max(native.width * ratio, 1), height: max(native.height * ratio, 1))
        }

        contentView.frame = CGRect(origin: .zero, size: contentSize)
        previewImageView.frame = contentView.bounds
        tileOverlayView.frame = contentView.bounds
        scrollView.contentSize = contentSize
        centerContentIfNeeded()
        if needsInitialPosition {
            let left = -scrollView.contentInset.left
            let right = max(contentSize.width - bounds.width + scrollView.contentInset.right, left)
            let x: CGFloat
            switch configuration.zoomStart {
            case .right: x = right
            case .center, .automatic: x = (left + right) / 2
            case .left: x = left
            }
            scrollView.contentOffset = CGPoint(x: x, y: -scrollView.contentInset.top)
            needsInitialPosition = false
        }
        updatePanBehavior()
        updateVisibleTiles()
    }

    private func centerContentIfNeeded() {
        let horizontalInset = max((bounds.width - scrollView.contentSize.width) / 2, 0)
        let verticalInset = max((bounds.height - scrollView.contentSize.height) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
        stabilizeContentOffsetIfNeeded()
    }

    private func visibleContentRect() -> CGRect {
        scrollView.convert(scrollView.bounds, to: contentView)
    }

    private func updateVisibleTiles() {
        guard let configuration else { return }
        guard configuration.allowsDetailTiles == true else {
            removeAllTiles()
            publishViewportState()
            return
        }
        guard contentView.bounds.width > 0, contentView.bounds.height > 0 else { return }
        let needsRestingDetailTiles = configuration.allowsDetailTiles && needsDetailTilesAtRest
        guard scrollView.zoomScale > 1.01 || needsRestingDetailTiles else {
            removeAllTiles()
            publishViewportState()
            return
        }

        let scale = traitCollection.displayScale * scrollView.zoomScale
        let expandedVisibleRect = visibleContentRect().insetBy(dx: -160, dy: -160)
        let effectiveTileLength = tileLength
        let minColumn = max(Int(floor(expandedVisibleRect.minX / effectiveTileLength)), 0)
        let maxColumn = max(Int(floor(expandedVisibleRect.maxX / effectiveTileLength)), minColumn)
        let minRow = max(Int(floor(expandedVisibleRect.minY / effectiveTileLength)), 0)
        let maxRow = max(Int(floor(expandedVisibleRect.maxY / effectiveTileLength)), minRow)

        var neededKeys = Set<ReaderTileCacheKey>()

        for row in minRow...maxRow {
            for column in minColumn...maxColumn {
                let tileRect = CGRect(
                    x: CGFloat(column) * effectiveTileLength,
                    y: CGFloat(row) * effectiveTileLength,
                    width: effectiveTileLength,
                    height: effectiveTileLength
                ).intersection(contentView.bounds)
                guard !tileRect.isNull, tileRect.width > 0, tileRect.height > 0 else { continue }

                let normalizedTileRect = CGRect(
                    x: tileRect.minX / contentView.bounds.width,
                    y: tileRect.minY / contentView.bounds.height,
                    width: tileRect.width / contentView.bounds.width,
                    height: tileRect.height / contentView.bounds.height
                )
                let absoluteCropRect = effectiveCropRect.subrect(normalizedTileRect)
                let request = ReaderTileRequest(
                    source: configuration.source,
                    normalizedCropRect: absoluteCropRect,
                    targetPixelSize: CGSize(
                        width: tileRect.width * max(scale, traitCollection.displayScale * 1.25),
                        height: tileRect.height * max(scale, traitCollection.displayScale * 1.25)
                    ),
                    colorTransform: configuration.colorTransform
                )
                let key = request.cacheKey
                neededKeys.insert(key)

                let imageView = tileViews[key] ?? {
                    let view = UIImageView(frame: tileRect)
                    view.backgroundColor = .clear
                    view.clipsToBounds = true
                    view.contentMode = .scaleToFill
                    tileOverlayView.addSubview(view)
                    tileViews[key] = view
                    return view
                }()
                imageView.frame = tileRect

                guard tileTasks[key] == nil, imageView.image == nil else { continue }

                let generation = currentGeneration
                let task = Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        let tileImage = try await self.imagePipeline.tileImage(
                            for: request,
                            variantKey: configuration.variantKey,
                            forceRefresh: configuration.retryToken > 0
                        )
                        guard self.currentGeneration == generation else { return }
                        self.tileViews[key]?.image = tileImage
                        self.tileTasks[key] = nil
                    } catch {
                        self.tileTasks[key] = nil
                    }
                }
                tileTasks[key] = task
            }
        }

        let staleKeys = Set(tileViews.keys).subtracting(neededKeys)
        for key in staleKeys {
            tileTasks[key]?.cancel()
            tileTasks[key] = nil
            tileViews[key]?.removeFromSuperview()
            tileViews[key] = nil
        }
    }

    private func removeAllTiles() {
        tileTasks.values.forEach { $0.cancel() }
        tileTasks.removeAll()
        tileViews.values.forEach { $0.removeFromSuperview() }
        tileViews.removeAll()
    }

    private func armEdgeTurnIfNeeded() {
        guard canTurnPagesFromHorizontalEdges else { return }
        let contentWidth = scrollView.contentSize.width
        let leftBoundary = -scrollView.adjustedContentInset.left + 1
        let rightBoundary = contentWidth - scrollView.bounds.width + scrollView.adjustedContentInset.right - 1
        if scrollView.contentOffset.x <= leftBoundary {
            didArmRightPageTurn = true
        }
        if scrollView.contentOffset.x >= rightBoundary {
            didArmLeftPageTurn = true
        }
    }

    private func publishViewportState(event: ReaderSurfaceEvent = .viewport, identity: ReaderSurfaceIdentity? = nil) {
        guard let identity = identity ?? surfaceIdentity else { return }
        stabilizeContentOffsetIfNeeded()

        let contentWidth = scrollView.contentSize.width
        let leftBoundary = -scrollView.adjustedContentInset.left + 1
        let rightBoundary = contentWidth - scrollView.bounds.width + scrollView.adjustedContentInset.right - 1
        let atLeftEdge = scrollView.contentOffset.x <= leftBoundary
        let atRightEdge = scrollView.contentOffset.x >= rightBoundary

        if !atLeftEdge {
            didArmRightPageTurn = false
        }
        if !atRightEdge {
            didArmLeftPageTurn = false
        }

        onViewportStateChanged?(
            ReaderPageViewportState(
                identity: identity, event: event,
                scale: scrollView.zoomScale,
                contentOffset: scrollView.contentOffset,
                isLeftEdgeReadyForPageTurn: canTurnPagesFromHorizontalEdges && didArmRightPageTurn,
                isRightEdgeReadyForPageTurn: canTurnPagesFromHorizontalEdges && didArmLeftPageTurn
            )
        )
    }

    private var centeredContentOffset: CGPoint {
        CGPoint(x: -scrollView.adjustedContentInset.left, y: -scrollView.adjustedContentInset.top)
    }

    private var hasHorizontallyScrollableContent: Bool {
        let visibleWidth = max(scrollView.bounds.width - scrollView.adjustedContentInset.left - scrollView.adjustedContentInset.right, 0)
        return scrollView.contentSize.width > visibleWidth + 1
    }

    private var hasVerticallyScrollableContent: Bool {
        let visibleHeight = max(scrollView.bounds.height - scrollView.adjustedContentInset.top - scrollView.adjustedContentInset.bottom, 0)
        return scrollView.contentSize.height > visibleHeight + 1
    }

    private var hasScrollableContent: Bool {
        hasHorizontallyScrollableContent || hasVerticallyScrollableContent
    }

    private var canTurnPagesFromHorizontalEdges: Bool {
        // Allow edge page turns even when horizontally unscrollable or unzoomed
        // so that users can swipe to the next page smoothly.
        return true
    }

    private func updatePanBehavior() {
        scrollView.panGestureRecognizer.isEnabled = hasScrollableContent
        scrollView.alwaysBounceHorizontal = hasHorizontallyScrollableContent
        scrollView.alwaysBounceVertical = hasVerticallyScrollableContent
        scrollView.bounces = hasScrollableContent
        if !canTurnPagesFromHorizontalEdges {
            didArmLeftPageTurn = false
            didArmRightPageTurn = false
        }
    }

    private func stabilizeContentOffsetIfNeeded() {
        let centeredOffset = centeredContentOffset
        var targetOffset = scrollView.contentOffset
        if !hasHorizontallyScrollableContent {
            targetOffset.x = centeredOffset.x
        }
        if !hasVerticallyScrollableContent {
            targetOffset.y = centeredOffset.y
        }
        guard targetOffset != scrollView.contentOffset else { return }
        scrollView.contentOffset = targetOffset
    }

    private var needsDetailTilesAtRest: Bool {
        guard let previewImage = previewImageView.image else { return false }
        guard contentView.bounds.width > 0, contentView.bounds.height > 0 else { return false }

        let requiredWidth = contentView.bounds.width * traitCollection.displayScale
        let requiredHeight = contentView.bounds.height * traitCollection.displayScale
        let availableWidth = previewImage.size.width * previewImage.scale
        let availableHeight = previewImage.size.height * previewImage.scale

        return availableWidth < requiredWidth * 0.98 || availableHeight < requiredHeight * 0.98
    }

    @objc
    private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard configuration?.allowsZoom == true else { return }
        guard recognizer.state == .ended else { return }

        let zoomingOut = scrollView.zoomScale > 1.01
        let targetScale = zoomingOut ? scrollView.minimumZoomScale : min(scrollView.maximumZoomScale, 2)
        guard zoomingOut || targetScale > scrollView.minimumZoomScale else { return }
        let tapPoint = recognizer.location(in: contentView)
        let zoomRect = CGRect(
            x: tapPoint.x - (scrollView.bounds.width / targetScale) * 0.5,
            y: tapPoint.y - (scrollView.bounds.height / targetScale) * 0.5,
            width: scrollView.bounds.width / targetScale,
            height: scrollView.bounds.height / targetScale
        )
        let animate = configuration?.animateZoom == true && !UIAccessibility.isReduceMotionEnabled
        // Replacement animations retain the activity continuously. Their old
        // completions cannot end a newer animation, even on the same host/load.
        cancelAnimatedZoom(release: !animate)
        guard animate, let identity = surfaceIdentity else {
            if zoomingOut { scrollView.setZoomScale(targetScale, animated: false) }
            else { scrollView.zoom(to: zoomRect, animated: false) }
            return
        }
        let animationID = UUID()
        animatedZoomIdentity = identity
        animatedZoomID = animationID
        publishViewportState(event: .begin(.animatedZoom), identity: identity)
        let animator = UIViewPropertyAnimator(duration: 0.25, curve: .easeInOut) { [weak self] in
            guard let self else { return }
            if zoomingOut { self.scrollView.setZoomScale(targetScale, animated: false) }
            else { self.scrollView.zoom(to: zoomRect, animated: false) }
        }
        animator.addCompletion { [weak self] _ in
            guard let self, self.animatedZoomID == animationID else { return }
            self.animatedZoomID = nil
            self.animatedZoomIdentity = nil
            self.zoomAnimator = nil
            self.publishViewportState(event: .end(.animatedZoom), identity: identity)
        }
        zoomAnimator = animator
        animator.startAnimation()
    }

    private func estimateLuminance(for image: UIImage) -> CGFloat {
        guard let cgImage = image.cgImage else { return 0.5 }

        let ciImage = CIImage(cgImage: cgImage)
        let filter = CIFilter(name: "CIAreaAverage")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(CIVector(cgRect: ciImage.extent), forKey: kCIInputExtentKey)

        guard let outputImage = filter?.outputImage else { return 0.5 }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        let red = CGFloat(bitmap[0]) / 255
        let green = CGFloat(bitmap[1]) / 255
        let blue = CGFloat(bitmap[2]) / 255
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}

private extension CGRect {
    func subrect(_ child: CGRect) -> CGRect {
        CGRect(
            x: origin.x + size.width * child.origin.x,
            y: origin.y + size.height * child.origin.y,
            width: size.width * child.size.width,
            height: size.height * child.size.height
        )
    }
}
