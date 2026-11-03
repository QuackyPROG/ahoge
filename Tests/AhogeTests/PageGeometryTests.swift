import UIKit
import XCTest
@testable import Ahoge

final class PageGeometryTests: XCTestCase {
    /// A `width`×`height` image filled with `background`, with `fill` drawn in each rect (top-left origin).
    private func image(_ width: Int, _ height: Int, background: UIColor, fill: UIColor, rects: [CGRect]) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            background.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            fill.setFill()
            for rect in rects { context.fill(rect) }
        }
        return image.cgImage!
    }

    /// The gray level (0...255) at the centre of `image`.
    private func centreGray(_ image: CGImage) -> UInt8 {
        var pixel: [UInt8] = [0]
        pixel.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 1, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            context.draw(image, in: CGRect(x: -CGFloat(image.width / 2), y: -CGFloat(image.height / 2), width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        return pixel[0]
    }

    func testWhiteBorderIsTrimmed() {
        let page = image(100, 100, background: .white, fill: .black, rects: [CGRect(x: 20, y: 10, width: 60, height: 70)])
        XCTAssertEqual(PageGeometry.contentRect(of: page), CGRect(x: 20, y: 10, width: 60, height: 70))
    }

    func testBlackBorderIsTrimmed() {
        let page = image(100, 100, background: .black, fill: .white, rects: [CGRect(x: 5, y: 25, width: 85, height: 50)])
        XCTAssertEqual(PageGeometry.contentRect(of: page), CGRect(x: 5, y: 25, width: 85, height: 50))
    }

    func testFullBleedPageIsLeftWhole() {
        // Black and white quarters: every row and column holds both colours.
        let page = image(100, 100, background: .white, fill: .black, rects: [CGRect(x: 0, y: 0, width: 50, height: 50), CGRect(x: 50, y: 50, width: 50, height: 50)])
        XCTAssertEqual(PageGeometry.contentRect(of: page), CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    func testMarginsDeeperThanThirtyPercentAreLeftAlone() {
        // A small drawing on a mostly white page: 40% white on every side.
        let page = image(100, 100, background: .white, fill: .black, rects: [CGRect(x: 40, y: 40, width: 20, height: 20)])
        XCTAssertEqual(PageGeometry.contentRect(of: page), CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    func testBorderIsFoundOnALargePage() {
        // 1000 px is sampled at 256 px, so the edges land within a few pixels.
        let page = image(1000, 1000, background: .white, fill: .black, rects: [CGRect(x: 100, y: 200, width: 800, height: 600)])
        let rect = PageGeometry.contentRect(of: page)
        XCTAssertEqual(rect.minX, 100, accuracy: 6)
        XCTAssertEqual(rect.minY, 200, accuracy: 6)
        XCTAssertEqual(rect.maxX, 900, accuracy: 6)
        XCTAssertEqual(rect.maxY, 800, accuracy: 6)
    }

    func testSplitOrderFollowsReadingDirection() {
        // Left half black, right half white.
        let spread = image(200, 100, background: .white, fill: .black, rects: [CGRect(x: 0, y: 0, width: 100, height: 100)])
        let leftToRight = PageGeometry.split(spread, rightToLeft: false)
        XCTAssertEqual(leftToRight.first.width, 100)
        XCTAssertLessThan(centreGray(leftToRight.first), 30)
        XCTAssertGreaterThan(centreGray(leftToRight.second), 225)
        let rightToLeft = PageGeometry.split(spread, rightToLeft: true)
        XCTAssertGreaterThan(centreGray(rightToLeft.first), 225)
        XCTAssertLessThan(centreGray(rightToLeft.second), 30)
    }

    func testWideAndRotate() throws {
        XCTAssertTrue(PageGeometry.isWide(CGSize(width: 200, height: 100)))
        XCTAssertFalse(PageGeometry.isWide(CGSize(width: 100, height: 200)))
        let spread = image(200, 100, background: .white, fill: .black, rects: [])
        let turned = try XCTUnwrap(PageGeometry.rotate(spread, clockwise: true))
        XCTAssertEqual(turned.width, 100)
        XCTAssertEqual(turned.height, 200)
    }

    func testTransformKeysAndHalves() throws {
        XCTAssertEqual(ImageLoader.cacheKey("https://x/p.jpg", maxPixelWidth: ImageLoader.maxPixelWidth, transform: ImageTransform()), "https://x/p.jpg")
        XCTAssertEqual(ImageLoader.cacheKey("https://x/p.jpg", maxPixelWidth: ImageLoader.maxPixelWidth, transform: ImageTransform(cropBorders: true, grayscale: true)), "https://x/p.jpg#tcg")
        XCTAssertEqual(ImageLoader.cacheKey("https://x/p.jpg", maxPixelWidth: ImageLoader.maxPixelWidth, transform: ImageTransform(half: .second, splitRightToLeft: true)), "https://x/p.jpg#t2r")

        let spread = UIImage(cgImage: image(200, 100, background: .white, fill: .black, rects: [CGRect(x: 0, y: 0, width: 100, height: 100)]))
        let first = try XCTUnwrap(ImageTransform(half: .first).apply(to: spread).cgImage)
        XCTAssertEqual(first.width, 100)
        XCTAssertLessThan(centreGray(first), 30)
        let inverted = try XCTUnwrap(ImageTransform(half: .first, invert: true).apply(to: spread).cgImage)
        XCTAssertGreaterThan(centreGray(inverted), 225)
    }
}
