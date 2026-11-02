import UIKit
import XCTest
@testable import Ahoge

final class ImageLoaderTests: XCTestCase {
    private func png(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.pngData()!
    }

    func testWideImageIsDecodedAtTheLimit() throws {
        let image = try XCTUnwrap(ImageLoader.decode(png(width: 3000, height: 1000), maxPixelWidth: 600))
        XCTAssertEqual(image.cgImage?.width, 600)
        XCTAssertEqual(image.cgImage?.height, 200)
    }

    func testTallStripKeepsItsWidthLimit() throws {
        let image = try XCTUnwrap(ImageLoader.decode(png(width: 3000, height: 9000), maxPixelWidth: 2048))
        XCTAssertEqual(image.cgImage?.width, 2048)
    }

    func testSmallImageIsNotScaled() throws {
        let image = try XCTUnwrap(ImageLoader.decode(png(width: 300, height: 450), maxPixelWidth: 600))
        XCTAssertEqual(image.cgImage?.width, 300)
    }

    func testCacheKeys() {
        XCTAssertEqual(ImageLoader.cacheKey("https://x/p.jpg", maxPixelWidth: ImageLoader.maxPixelWidth), "https://x/p.jpg")
        XCTAssertEqual(ImageLoader.cacheKey("https://x/p.jpg", maxPixelWidth: 360), "https://x/p.jpg#w360")
    }

    func testGarbageIsNil() {
        XCTAssertNil(ImageLoader.decode(Data("not an image".utf8), maxPixelWidth: 600))
    }
}
