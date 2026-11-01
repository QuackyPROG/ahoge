import SwiftUI
import UIKit

/// A page in the paged modes: fitted to the screen, pinch and double tap to zoom. Single taps
/// report where they landed (0...1 on each axis) once a double tap is ruled out.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> ZoomingImageView { ZoomingImageView() }

    func updateUIView(_ view: ZoomingImageView, context: Context) {
        view.image = image
        view.onTap = onTap
    }
}

final class ZoomingImageView: UIScrollView, UIScrollViewDelegate {
    var onTap: ((CGPoint) -> Void)?
    private let imageView = UIImageView()
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

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
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
        // First layout, a new image, or a rotation: fit the image again, unzoomed.
        if fittedBounds != bounds.size {
            fittedBounds = bounds.size
            zoomScale = 1
            let scale = min(bounds.width / size.width, bounds.height / size.height)
            imageView.frame = CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
            contentSize = imageView.frame.size
            centerImage()
            contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }

    /// Keeps an image smaller than the screen in the middle of it.
    private func centerImage() {
        let x = max(0, (bounds.width - contentSize.width) / 2)
        let y = max(0, (bounds.height - contentSize.height) / 2)
        let inset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        if contentInset != inset { contentInset = inset }
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let scale: CGFloat = 2.5
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }

    @objc private func singleTapped(_ gesture: UITapGestureRecognizer) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        // bounds.origin is the scroll offset, so this is the point on screen.
        let point = gesture.location(in: self)
        onTap?(CGPoint(x: (point.x - bounds.minX) / bounds.width, y: (point.y - bounds.minY) / bounds.height))
    }
}
