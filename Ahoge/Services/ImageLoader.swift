import UIKit
import ImageIO

/// Decoded images by URL. Thread-safe, so views can read a hit synchronously while laying out
/// and show a cached page on their first frame instead of a placeholder.
final class ImageMemoryCache: @unchecked Sendable {
    static let shared = ImageMemoryCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() { cache.totalCostLimit = 200 << 20 }

    subscript(url: String) -> UIImage? { cache.object(forKey: url as NSString) }

    func insert(_ image: UIImage, for url: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: url as NSString, cost: cost)
    }

    func removeAll() { cache.removeAllObjects() }
}

/// Loads images with per-request headers (Referer), memory and disk cached, de-duplicated.
actor ImageLoader {
    static let shared = ImageLoader()

    /// Wider images are scaled down while decoding: a phone or tablet never shows more pixels than
    /// this across, and a full-size webtoon strip costs tens of megabytes of memory.
    nonisolated static let maxPixelWidth: CGFloat = 2048

    private let session: URLSession
    private var inFlight: [String: Task<UIImage, Error>] = [:]

    init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 50 << 20, diskCapacity: 500 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpCookieStorage = .shared
        session = URLSession(configuration: config)
    }

    /// The memory-cache key: the URL for full-size pages (so the reader can read hits by URL),
    /// the URL plus the width for smaller decodes such as covers.
    nonisolated static func cacheKey(_ url: String, maxPixelWidth: CGFloat) -> String {
        maxPixelWidth >= Self.maxPixelWidth ? url : "\(url)#w\(Int(maxPixelWidth))"
    }

    func image(_ url: String, headers: [String: String] = [:], maxPixelWidth: CGFloat = ImageLoader.maxPixelWidth, priority: TaskPriority = .userInitiated) async throws -> UIImage {
        let key = Self.cacheKey(url, maxPixelWidth: maxPixelWidth)
        if let hit = ImageMemoryCache.shared[key] { return hit }
        // Awaiting a running low-priority prefetch raises its priority to ours.
        if let running = inFlight[key] { return try await running.value }
        let session = session
        let task = Task.detached(priority: priority) { () throws -> UIImage in
            guard let target = URL(string: url) else { throw URLError(.badURL) }
            // Downloaded pages: read from disk, same downsampling, no network.
            if target.isFileURL {
                guard let image = Self.decode(try Data(contentsOf: target), maxPixelWidth: maxPixelWidth) else { throw URLError(.cannotDecodeContentData) }
                return image
            }
            var request = URLRequest(url: target)
            request.setValue(HTTPClient.defaultUserAgent, forHTTPHeaderField: "User-Agent")
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            guard let image = Self.decode(data, maxPixelWidth: maxPixelWidth) else { throw URLError(.cannotDecodeContentData) }
            return image
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let image = try await task.value
        ImageMemoryCache.shared.insert(image, for: key)
        return image
    }

    /// Reader prefetches run below the page on screen, so they never slow it down.
    func prefetch(_ url: String, headers: [String: String]) {
        Task(priority: .utility) { _ = try? await image(url, headers: headers, priority: .utility) }
    }

    /// Bytes the image cache holds on disk.
    func diskUsage() -> Int { session.configuration.urlCache?.currentDiskUsage ?? 0 }

    func clear() {
        ImageMemoryCache.shared.removeAll()
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    /// Decodes off the main thread, straight to at most `maxPixelWidth` across: ImageIO never
    /// holds the full-size bitmap, so a 4000 px cover costs what a 360 px one does.
    nonisolated static func decode(_ data: Data, maxPixelWidth: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        var width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        var height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        // The pixel size is before rotation, the thumbnail after it: orientations 5-8 turn the image.
        if let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue, orientation >= 5 {
            swap(&width, &height)
        }
        if width > 0, height > 0, width <= maxPixelWidth {
            guard let image = UIImage(data: data) else { return nil }
            return image.preparingForDisplay() ?? image
        }
        // The thumbnail limit applies to the longer side. Unknown dimensions stay capped at the width limit.
        let longest = width > 0 && height > 0 ? max(maxPixelWidth, (height * maxPixelWidth / width).rounded()) : maxPixelWidth
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
