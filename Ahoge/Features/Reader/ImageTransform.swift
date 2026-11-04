import CoreImage
import UIKit

/// What the reader changes about a page after decoding it. Part of `ImageLoader`'s cache key, so a
/// cropped or grayscale page is decoded once and the plain one stays cached beside it.
struct ImageTransform: Hashable, Sendable {
    /// One side of a split spread, in reading order.
    enum Half: String, Hashable, Sendable { case first, second }

    var cropBorders = false
    /// Shows only this half of a wide page.
    var half: Half?
    /// Reading order of the halves: right half first.
    var splitRightToLeft = false
    /// Turns wide pages a quarter turn so they fill a portrait screen.
    var rotateWide = false
    var grayscale = false
    var invert = false

    static let plain = ImageTransform()

    /// Nothing to do (the split order alone changes nothing without a half).
    var isIdentity: Bool { !cropBorders && half == nil && !rotateWide && !grayscale && !invert }

    /// Appended to the cache key; empty for `plain`, so a plain page's key stays its URL.
    var cacheSuffix: String {
        guard !isIdentity else { return "" }
        var suffix = "#t"
        if cropBorders { suffix += "c" }
        if let half { suffix += (half == .first ? "1" : "2") + (splitRightToLeft ? "r" : "l") }
        if rotateWide { suffix += "o" }
        if grayscale { suffix += "g" }
        if invert { suffix += "i" }
        return suffix
    }

    /// Runs off the main actor (inside `ImageLoader`); returns `image` when there is nothing to do.
    func apply(to image: UIImage) -> UIImage {
        guard !isIdentity, var page = image.cgImage else { return image }
        if cropBorders { page = page.cropping(to: PageGeometry.contentRect(of: page)) ?? page }
        let wide = PageGeometry.isWide(CGSize(width: page.width, height: page.height))
        if let half, wide {
            let halves = PageGeometry.split(page, rightToLeft: splitRightToLeft)
            page = half == .first ? halves.first : halves.second
        } else if rotateWide, wide {
            page = PageGeometry.rotate(page, clockwise: true) ?? page
        }
        if grayscale || invert { page = Self.filter(page, grayscale: grayscale, invert: invert) ?? page }
        return UIImage(cgImage: page, scale: image.scale, orientation: image.imageOrientation)
    }

    private static let context = CIContext()

    private static func filter(_ image: CGImage, grayscale: Bool, invert: Bool) -> CGImage? {
        var output = CIImage(cgImage: image)
        if grayscale, let filter = CIFilter(name: "CIColorControls") {
            filter.setValue(output, forKey: kCIInputImageKey)
            filter.setValue(0.0, forKey: kCIInputSaturationKey)
            if let result = filter.outputImage { output = result }
        }
        if invert, let filter = CIFilter(name: "CIColorInvert") {
            filter.setValue(output, forKey: kCIInputImageKey)
            if let result = filter.outputImage { output = result }
        }
        return context.createCGImage(output, from: output.extent)
    }
}
