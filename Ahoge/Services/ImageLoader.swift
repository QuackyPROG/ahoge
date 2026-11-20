import UIKit
import ImageIO

/// Decoded images by URL. Thread-safe, so views can read a hit synchronously while laying out
/// and show a cached page on their first frame instead of a placeholder.
final class ImageMemoryCache: @unchecked Sendable {
    static let shared = ImageMemoryCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.totalCostLimit = 96 << 20
        // Decoded pages can be decoded again from the disk cache, so they go first when iOS needs memory.
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [cache] _ in
            cache.removeAllObjects()
        }
    }

    var costLimit: Int { cache.totalCostLimit }

    subscript(url: String) -> UIImage? { cache.object(forKey: url as NSString) }

    func insert(_ image: UIImage, for url: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: url as NSString, cost: cost)
    }

    func remove(_ url: String) { cache.removeObject(forKey: url as NSString) }

    func removeAll() { cache.removeAllObjects() }

    /// Untransformed sizes by plain cache key, kept after the image itself is gone (a transformed
    /// page does not keep its plain copy), so wide pages are still recognised.
    private var sizes: [String: CGSize] = [:]
    private let sizesLock = NSLock()

    func size(of url: String) -> CGSize? {
        sizesLock.lock()
        defer { sizesLock.unlock() }
        return sizes[url]
    }

    func recordSize(_ size: CGSize, for url: String) {
        sizesLock.lock()
        defer { sizesLock.unlock() }
        sizes[url] = size
    }
}

/// Loads images with per-request headers (Referer), memory and disk cached, de-duplicated.
actor ImageLoader {
    static let shared = ImageLoader()

    /// Wider images are scaled down while decoding: a phone or tablet never shows more pixels than
    /// this across, and a full-size webtoon strip costs tens of megabytes of memory.
    nonisolated static let maxPixelWidth: CGFloat = 2048
    /// No decoded page is longer than this, so one costs at most 2048 × 4096 × 4 B = 32 MiB.
    nonisolated static let maxPixelLength: CGFloat = 4096

    private let session: URLSession
    private var inFlight: [String: Task<UIImage, Error>] = [:]
    /// Tall pages being cut into slices, by page key; every slice of a page shares one decode.
    private var slicing: [String: Task<[UIImage], Error>] = [:]

    init() {
        let config = URLSessionConfiguration.default
        let urlCache = URLCache(memoryCapacity: Self.urlCacheMemory, diskCapacity: 500 << 20)
        config.urlCache = urlCache
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpCookieStorage = .shared
        session = URLSession(configuration: config)
        // Empties the memory copy only; the disk cache stays.
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { _ in
            urlCache.memoryCapacity = 0
            urlCache.memoryCapacity = Self.urlCacheMemory
        }
    }

    private nonisolated static let urlCacheMemory = 8 << 20

    /// The memory-cache key: the URL for full-size pages (so the reader can read hits by URL),
    /// the URL plus the width for smaller decodes such as covers, plus the reader's transform if any.
    nonisolated static func cacheKey(_ url: String, maxPixelWidth: CGFloat, transform: ImageTransform = .plain) -> String {
        (maxPixelWidth >= Self.maxPixelWidth ? url : "\(url)#w\(Int(maxPixelWidth))") + transform.cacheSuffix
    }

    func image(_ url: String, headers: [String: String] = [:], maxPixelWidth: CGFloat = ImageLoader.maxPixelWidth, transform: ImageTransform = .plain, priority: TaskPriority = .userInitiated) async throws -> UIImage {
        let key = Self.cacheKey(url, maxPixelWidth: maxPixelWidth, transform: transform)
        if let hit = ImageMemoryCache.shared[key] { return hit }
        // Awaiting a running low-priority prefetch raises its priority to ours.
        if let running = inFlight[key] { return try await running.value }
        guard transform.isIdentity else {
            // The plain page is fetched once (callers asking at the same time share it); each transform
            // of it is made off the actor. Only the transformed copy stays in memory.
            let plainKey = Self.cacheKey(url, maxPixelWidth: maxPixelWidth)
            let base = try await image(url, headers: headers, maxPixelWidth: maxPixelWidth, priority: priority)
            if let hit = ImageMemoryCache.shared[key] { return hit }
            if let running = inFlight[key] { return try await running.value }
            let made = try await run(Task.detached(priority: priority) { () throws -> UIImage in transform.apply(to: base) }, key: key)
            ImageMemoryCache.shared.remove(plainKey)
            return made
        }
        let session = session
        let task = Task.detached(priority: priority) { () throws -> UIImage in
            let data = try await Self.data(url, headers: headers, session: session)
            guard let image = Self.decode(data, maxPixelWidth: maxPixelWidth) else { throw URLError(.cannotDecodeContentData) }
            // Before the length limit, so a tall strip is still known to be one.
            if let size = Self.pixelSize(data, maxPixelWidth: maxPixelWidth) { ImageMemoryCache.shared.recordSize(size, for: key) }
            return image
        }
        return try await run(task, key: key)
    }

    /// The cache key of slice `index` of a tall page (see `slices`).
    nonisolated static func sliceKey(_ url: String, _ index: Int, transform: ImageTransform = .plain) -> String {
        cacheKey(url, maxPixelWidth: maxPixelWidth, transform: transform) + "#s\(index)"
    }

    /// Slice `index` of a tall webtoon page. The page is decoded once for all its slices, each cached
    /// under its own key; the whole strip is not kept.
    func slice(_ index: Int, of url: String, headers: [String: String] = [:], transform: ImageTransform = .plain, priority: TaskPriority = .userInitiated) async throws -> UIImage {
        let key = Self.sliceKey(url, index, transform: transform)
        if let hit = ImageMemoryCache.shared[key] { return hit }
        let pageKey = Self.cacheKey(url, maxPixelWidth: Self.maxPixelWidth, transform: transform)
        let slices: [UIImage]
        if let running = slicing[pageKey] {
            slices = try await running.value
        } else {
            let session = session
            let task = Task.detached(priority: priority) { () throws -> [UIImage] in
                let data = try await Self.data(url, headers: headers, session: session)
                let pieces = Self.slices(data, maxPixelWidth: Self.maxPixelWidth, transform: transform)
                guard !pieces.isEmpty else { throw URLError(.cannotDecodeContentData) }
                return pieces
            }
            slicing[pageKey] = task
            defer { slicing[pageKey] = nil }
            slices = try await task.value
            for (number, slice) in slices.enumerated() {
                ImageMemoryCache.shared.insert(slice, for: Self.sliceKey(url, number, transform: transform))
            }
        }
        guard slices.indices.contains(index) else { throw URLError(.cannotDecodeContentData) }
        return slices[index]
    }

    /// The image's bytes: read from disk for downloaded pages (no network), fetched otherwise.
    private nonisolated static func data(_ url: String, headers: [String: String], session: URLSession) async throws -> Data {
        guard let target = URL(string: url) else { throw URLError(.badURL) }
        if target.isFileURL { return try Data(contentsOf: target) }
        var request = URLRequest(url: target)
        request.setValue(HTTPClient.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// Shares `task` with other callers of `key` while it runs, then caches what it made.
    private func run(_ task: Task<UIImage, Error>, key: String) async throws -> UIImage {
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let image = try await task.value
        ImageMemoryCache.shared.insert(image, for: key)
        return image
    }

    /// Bytes the image cache holds on disk.
    func diskUsage() -> Int { session.configuration.urlCache?.currentDiskUsage ?? 0 }

    func clear() {
        ImageMemoryCache.shared.removeAll()
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    /// Decodes off the main thread, straight to at most `maxPixelWidth` across and `maxPixelLength`
    /// on the longer side: ImageIO never holds the full-size bitmap, so a 4000 px cover costs what a
    /// 360 px one does.
    nonisolated static func decode(_ data: Data, maxPixelWidth: CGFloat, maxPixelLength: CGFloat = ImageLoader.maxPixelLength) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let size = pixelSize(of: source)
        if let size, size.width <= maxPixelWidth, max(size.width, size.height) <= maxPixelLength {
            guard let image = UIImage(data: data) else { return nil }
            return image.preparingForDisplay() ?? image
        }
        // The thumbnail limit applies to the longer side. Unknown dimensions stay capped at the width limit.
        let longest = size.map { min(max($0.width, $0.height) * min(1, maxPixelWidth / $0.width), maxPixelLength).rounded() } ?? maxPixelWidth
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    /// The size `data` decodes to at most `maxPixelWidth` across, before the length limit; nil when unknown.
    nonisolated static func pixelSize(_ data: Data, maxPixelWidth: CGFloat) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0, let size = pixelSize(of: source) else { return nil }
        let scale = min(1, maxPixelWidth / size.width)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    /// The image's pixel size as shown (after its orientation); nil when unknown.
    private nonisolated static func pixelSize(of source: CGImageSource) -> CGSize? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        var width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        var height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        // The pixel size is before rotation, the thumbnail after it: orientations 5-8 turn the image.
        if let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue, orientation >= 5 {
            swap(&width, &height)
        }
        return width > 0 && height > 0 ? CGSize(width: width, height: height) : nil
    }

    /// A tall webtoon page at most `maxPixelWidth` across, cut top to bottom into slices at most
    /// `maxPixelLength` tall, each its own bitmap so the cache can drop them one at a time. The full
    /// strip exists only while it is cut.
    nonisolated static func slices(_ data: Data, maxPixelWidth: CGFloat, transform: ImageTransform = .plain) -> [UIImage] {
        guard let strip = decode(data, maxPixelWidth: maxPixelWidth, maxPixelLength: .infinity)?.cgImage else { return [] }
        var columns = CGRect(x: 0, y: 0, width: strip.width, height: strip.height)
        // Borders are trimmed at the sides only and across the whole strip, so slices line up and
        // the strip keeps the height its slices were counted from.
        if transform.cropBorders {
            let content = PageGeometry.contentRect(of: strip)
            columns.origin.x = content.minX
            columns.size.width = content.width
        }
        var rest = transform
        rest.cropBorders = false
        let rows = Int(maxPixelLength)
        var slices: [UIImage] = []
        for top in stride(from: 0, to: strip.height, by: rows) {
            let rect = CGRect(x: columns.minX, y: CGFloat(top), width: columns.width, height: CGFloat(min(rows, strip.height - top)))
            guard let piece = strip.cropping(to: rect), let copy = ownBitmap(piece) else { return [] }
            slices.append(rest.apply(to: UIImage(cgImage: copy)))
        }
        return slices
    }

    /// `image` drawn into a bitmap of its own; a cropped `CGImage` keeps its whole source alive.
    private nonisolated static func ownBitmap(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}
