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

    /// A JPEG of `width` × `height` raw pixels carrying EXIF `orientation`.
    private func jpeg(width: Int, height: Int, orientation: Int) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cgImage, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testRotatedPageDecodesUpright() throws {
        let image = try XCTUnwrap(ImageLoader.decode(jpeg(width: 100, height: 200, orientation: 6), maxPixelWidth: 2048))
        XCTAssertEqual(image.imageOrientation, .up)
        XCTAssertEqual(image.cgImage?.width, 200)
        XCTAssertEqual(image.cgImage?.height, 100)
    }

    func testRotatedPageSlicesAreUpright() throws {
        let slices = ImageLoader.slices(try jpeg(width: 100, height: 200, orientation: 6), maxPixelWidth: 2048)
        XCTAssertEqual(slices.count, 1)
        XCTAssertEqual(slices.first?.cgImage?.width, 200)
        XCTAssertEqual(slices.first?.cgImage?.height, 100)
    }

    func testRotatedPageSizeIsAsShown() throws {
        XCTAssertEqual(ImageLoader.pixelSize(try jpeg(width: 100, height: 200, orientation: 6), maxPixelWidth: 2048), CGSize(width: 200, height: 100))
    }

    func testWideImageIsDecodedAtTheLimit() throws {
        let image = try XCTUnwrap(ImageLoader.decode(png(width: 3000, height: 1000), maxPixelWidth: 600))
        XCTAssertEqual(image.cgImage?.width, 600)
        XCTAssertEqual(image.cgImage?.height, 200)
    }

    func testTallStripIsCappedAt4096PixelsLong() throws {
        let image = try XCTUnwrap(ImageLoader.decode(png(width: 800, height: 20000), maxPixelWidth: 2048))
        XCTAssertEqual(image.cgImage?.height, 4096)
    }

    func testTallStripSlicesAre4096PixelsLongAtMost() throws {
        let slices = ImageLoader.slices(png(width: 800, height: 20000), maxPixelWidth: 2048)
        XCTAssertEqual(slices.map { $0.cgImage?.width }, [800, 800, 800, 800, 800])
        XCTAssertEqual(slices.map { $0.cgImage?.height }, [4096, 4096, 4096, 4096, 3616])
    }

    func testHugeStripSlicesKeepTheWidthLimit() throws {
        let slices = autoreleasepool { ImageLoader.slices(png(width: 4000, height: 60000), maxPixelWidth: 2048) }
        XCTAssertEqual(slices.count, 8)
        for slice in slices {
            XCTAssertLessThanOrEqual(slice.cgImage?.width ?? .max, 2048)
            XCTAssertLessThanOrEqual(slice.cgImage?.height ?? .max, 4096)
        }
    }

    func testSmallImageIsNotScaled() throws {
        let image = try XCTUnwrap(ImageLoader.decode(png(width: 300, height: 450), maxPixelWidth: 600))
        XCTAssertEqual(image.cgImage?.width, 300)
    }

    func testCacheKeys() {
        XCTAssertEqual(ImageLoader.cacheKey("https://x/p.jpg", maxPixelWidth: ImageLoader.maxPixelWidth), "https://x/p.jpg")
        XCTAssertEqual(ImageLoader.cacheKey("https://x/p.jpg", maxPixelWidth: 360), "https://x/p.jpg#w360")
    }

    func testDecodedCacheHoldsAtMost96MiB() {
        XCTAssertEqual(ImageMemoryCache.shared.costLimit, 96 << 20)
    }

    func testMemoryWarningEmptiesTheDecodedCache() throws {
        let key = "test://memory-warning/\(UUID().uuidString)"
        ImageMemoryCache.shared.insert(try XCTUnwrap(UIImage(data: png(width: 10, height: 10))), for: key)
        XCTAssertNotNil(ImageMemoryCache.shared[key])
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertNil(ImageMemoryCache.shared[key])
    }

    func testTransformedPageKeepsOnlyTheTransformedCopyAndTheSize() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try png(width: 300, height: 450).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let url = file.absoluteString
        let transform = ImageTransform(grayscale: true)
        _ = try await ImageLoader.shared.image(url, transform: transform)
        XCTAssertNotNil(ImageMemoryCache.shared[ImageLoader.cacheKey(url, maxPixelWidth: ImageLoader.maxPixelWidth, transform: transform)])
        XCTAssertNil(ImageMemoryCache.shared[url])
        XCTAssertEqual(ImageMemoryCache.shared.size(of: url), CGSize(width: 300, height: 450))
    }

    func testSliceKeyKeepsTodaysKeyAtTheLimitAndChangesWithWidth() {
        let url = "https://x/p.jpg"
        let today = ImageLoader.cacheKey(url, maxPixelWidth: 2048) + "#s0"
        XCTAssertEqual(ImageLoader.sliceKey(url, 0), today)
        XCTAssertNotEqual(ImageLoader.sliceKey(url, 0, maxPixelWidth: 1179), today)
    }

    func testSliceDecodesAtTheGivenWidthAndCachesTheRest() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try png(width: 800, height: 20000).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let url = file.absoluteString
        let first = try await ImageLoader.shared.slice(0, of: url, maxPixelWidth: 400)
        XCTAssertEqual(first.cgImage?.width, 400)
        XCTAssertLessThanOrEqual(first.cgImage?.height ?? .max, 4096)
        XCTAssertEqual(ImageMemoryCache.shared.size(of: url), CGSize(width: 800, height: 20000))
        // At 400 wide the strip is 400 × 10000: three slices (4096, 4096, 1808).
        for index in 1..<3 {
            XCTAssertNotNil(ImageMemoryCache.shared[ImageLoader.sliceKey(url, index, maxPixelWidth: 400)])
        }
        XCTAssertNil(ImageMemoryCache.shared[ImageLoader.sliceKey(url, 3, maxPixelWidth: 400)])
    }

    func testShortPageIsOneSlice() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try png(width: 800, height: 1000).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let url = file.absoluteString
        let only = try await ImageLoader.shared.slice(0, of: url, maxPixelWidth: 400)
        XCTAssertEqual(only.cgImage?.width, 400)
        XCTAssertEqual(only.cgImage?.height, 500)
        do {
            _ = try await ImageLoader.shared.slice(1, of: url, maxPixelWidth: 400)
            XCTFail("there is no second slice")
        } catch {
            XCTAssertEqual(error as? URLError, URLError(.cannotDecodeContentData))
        }
    }

    func testGarbageIsNil() {
        XCTAssertNil(ImageLoader.decode(Data("not an image".utf8), maxPixelWidth: 600))
    }
}
