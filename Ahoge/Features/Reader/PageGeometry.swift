import CoreGraphics

/// Page shapes the reader changes at decode time: trimmed margins, wide pages cut in two or turned.
/// Pure CoreGraphics, so it runs off the main actor inside `ImageLoader` and is tested on synthetic images.
enum PageGeometry {
    /// Crop detection looks at a copy at most this many pixels across; margins don't need more.
    static let sampleSize = 256
    /// An edge whose margin runs deeper than this is left alone: it is a white panel, not a border.
    static let maxCropFraction = 0.3

    /// The part of `image` inside its near-uniform margins, in pixels with the origin at the top left
    /// (what `CGImage.cropping(to:)` takes). The whole image when there is nothing to trim.
    static func contentRect(of image: CGImage, threshold: UInt8 = 10) -> CGRect {
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard image.width > 2, image.height > 2 else { return full }
        let scale = min(1, Double(sampleSize) / Double(max(image.width, image.height)))
        let w = max(1, Int((Double(image.width) * scale).rounded()))
        let h = max(1, Int((Double(image.height) * scale).rounded()))
        var pixels = [UInt8](repeating: 0, count: w * h)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return full }

        // The bitmap's first row is the top of the image.
        func value(_ x: Int, _ y: Int) -> Int { Int(pixels[y * w + x]) }
        func rowMatches(_ y: Int, _ reference: Int) -> Bool {
            (0..<w).allSatisfy { abs(value($0, y) - reference) <= Int(threshold) }
        }
        func columnMatches(_ x: Int, _ reference: Int) -> Bool {
            (0..<h).allSatisfy { abs(value(x, $0) - reference) <= Int(threshold) }
        }
        /// How many lines from one edge match that edge's colour; 0 when the margin is too deep to be a border.
        func depth(_ count: Int, _ matches: (Int) -> Bool) -> Int {
            let limit = Int(Double(count) * maxCropFraction)
            var depth = 0
            while depth <= limit, matches(depth) { depth += 1 }
            return depth > limit ? 0 : depth
        }

        let top = depth(h) { rowMatches($0, value(0, 0)) }
        let bottom = depth(h) { rowMatches(h - 1 - $0, value(0, h - 1)) }
        let left = depth(w) { columnMatches($0, value(0, 0)) }
        let right = depth(w) { columnMatches(w - 1 - $0, value(w - 1, 0)) }
        guard top + bottom < h, left + right < w else { return full }

        let sx = Double(image.width) / Double(w), sy = Double(image.height) / Double(h)
        let minX = (Double(left) * sx).rounded(.down), maxX = (Double(w - right) * sx).rounded(.up)
        let minY = (Double(top) * sy).rounded(.down), maxY = (Double(h - bottom) * sy).rounded(.up)
        return CGRect(x: minX, y: minY, width: min(Double(image.width), maxX) - minX, height: min(Double(image.height), maxY) - minY)
    }

    /// A double-page spread: wider than tall.
    static func isWide(_ size: CGSize) -> Bool { size.width > size.height }

    /// The two halves of a spread in reading order: left then right, or right then left.
    static func split(_ image: CGImage, rightToLeft: Bool) -> (first: CGImage, second: CGImage) {
        let half = image.width / 2
        let left = image.cropping(to: CGRect(x: 0, y: 0, width: half, height: image.height)) ?? image
        let right = image.cropping(to: CGRect(x: half, y: 0, width: image.width - half, height: image.height)) ?? image
        return rightToLeft ? (right, left) : (left, right)
    }

    /// The image turned a quarter turn, so a spread fills a portrait screen.
    static func rotate(_ image: CGImage, clockwise: Bool) -> CGImage? {
        let w = image.width, h = image.height
        guard let context = CGContext(
            data: nil, width: h, height: w, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        // CoreGraphics has y up: a clockwise turn is a negative angle.
        if clockwise {
            context.translateBy(x: 0, y: CGFloat(w))
            context.rotate(by: -.pi / 2)
        } else {
            context.translateBy(x: CGFloat(h), y: 0)
            context.rotate(by: .pi / 2)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
    }
}
