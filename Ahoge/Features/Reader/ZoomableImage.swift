import SwiftUI
import UIKit

/// How a paged page is sized and zoomed (the reader's paged settings).
struct ZoomOptions: Equatable {
    var scale: ReaderScaleType = .fitScreen
    var start: ReaderZoomStart = .auto
    /// Auto start position begins on the right.
    var rightToLeft = false
    /// Wide pages open at full height, to pan across.
    var panWide = false
    var doubleTapZoom = true
    /// Pinching can't go below the starting size.
    var disableZoomOut = false
    /// Seconds; 0 zooms without animation.
    var doubleTapDuration: Double = 0.3
    /// Where a page narrower than its frame sits: 0 leading, 0.5 centre, 1 trailing (the two halves of a spread).
    var horizontalAlignment: CGFloat = 0.5
}

/// A page in the paged modes: sized by `options`, pinch and double tap to zoom. Single taps
/// report where they landed (0...1 on each axis) once a double tap is ruled out.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    var options = ZoomOptions()
    let onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> ZoomingImageView { ZoomingImageView() }

    func updateUIView(_ view: ZoomingImageView, context: Context) {
        view.image = image
        view.options = options
        view.onTap = onTap
    }
}

final class ZoomingImageView: UIScrollView, UIScrollViewDelegate {
    var onTap: ((CGPoint) -> Void)?
    private let imageView = UIImageView()
    private let doubleTap = UITapGestureRecognizer()
    private var fittedBounds = CGSize.zero

    var image: UIImage? {
        get { imageView.image }
        set {
            guard newValue !== imageView.image else { return }
            imageView.image = newValue
            fittedBounds = .zero
            setNeedsLayout()
        }
    }

    var options = ZoomOptions() {
        didSet {
            guard options != oldValue else { return }
            doubleTap.isEnabled = options.doubleTapZoom
            imageView.contentMode = options.scale == .stretch ? .scaleToFill : .scaleAspectFit
            fittedBounds = .zero
            setNeedsLayout()
        }
    }

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        bouncesZoom = true
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        doubleTap.addTarget(self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped(_:)))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let size = imageView.image?.size, size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        // First layout, a new image, new options or a rotation: size the image again, unzoomed.
        if fittedBounds != bounds.size {
            fittedBounds = bounds.size
            zoomScale = 1
            let fitScreen = min(bounds.width / size.width, bounds.height / size.height)
            let scale = baseScale(for: size)
            minimumZoomScale = options.disableZoomOut ? 1 : min(1, fitScreen / scale)
            maximumZoomScale = 4
            let fitted = options.scale == .stretch && !(options.panWide && PageGeometry.isWide(size))
                ? bounds.size
                : CGSize(width: size.width * scale, height: size.height * scale)
            imageView.frame = CGRect(origin: .zero, size: fitted)
            contentSize = fitted
            centerImage()
            contentOffset = startOffset()
        }
    }

    /// Image points to screen points before any zoom.
    private func baseScale(for size: CGSize) -> CGFloat {
        let fitWidth = bounds.width / size.width
        let fitHeight = bounds.height / size.height
        let wide = PageGeometry.isWide(size)
        if options.panWide, wide { return fitHeight }
        switch options.scale {
        case .fitScreen, .stretch: return min(fitWidth, fitHeight)
        case .fitWidth: return fitWidth
        case .fitHeight: return fitHeight
        // One image pixel per screen pixel.
        case .original: return (imageView.image?.scale ?? 1) / max(traitCollection.displayScale, 1)
        case .smartFit: return wide ? fitHeight : fitWidth
        }
    }

    /// The first part of a page larger than the screen to show: its top, at the chosen side.
    private func startOffset() -> CGPoint {
        let overflow = max(0, contentSize.width - bounds.width)
        let x: CGFloat
        switch options.start {
        case .auto: x = options.rightToLeft ? overflow : 0
        case .left: x = 0
        case .right: x = overflow
        case .center: x = overflow / 2
        }
        return CGPoint(x: x - contentInset.left, y: -contentInset.top)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }

    /// Keeps an image smaller than the screen in the middle of it (or at its side, in a spread).
    private func centerImage() {
        let freeX = max(0, bounds.width - contentSize.width)
        let freeY = max(0, bounds.height - contentSize.height)
        let left = freeX * options.horizontalAlignment
        let inset = UIEdgeInsets(top: freeY / 2, left: left, bottom: freeY / 2, right: freeX - left)
        if contentInset != inset { contentInset = inset }
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        let duration = options.doubleTapDuration
        let change: () -> Void
        if abs(zoomScale - 1) > 0.01 {
            change = { self.zoomScale = 1 }
        } else {
            let point = gesture.location(in: imageView)
            let scale: CGFloat = 2.5
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            let target = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
            change = { self.zoom(to: target, animated: false) }
        }
        if duration > 0 {
            UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: change)
        } else {
            change()
        }
    }

    @objc private func singleTapped(_ gesture: UITapGestureRecognizer) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        // bounds.origin is the scroll offset, so this is the point on screen.
        let point = gesture.location(in: self)
        onTap?(CGPoint(x: (point.x - bounds.minX) / bounds.width, y: (point.y - bounds.minY) / bounds.height))
    }
}
