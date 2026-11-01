import UIKit

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

    func image(_ url: String, headers: [String: String] = [:]) async throws -> UIImage {
        if let hit = ImageMemoryCache.shared[url] { return hit }
        if let running = inFlight[url] { return try await running.value }
        let session = session
        let task = Task.detached(priority: .userInitiated) { () throws -> UIImage in
            guard let target = URL(string: url) else { throw URLError(.badURL) }
            var request = URLRequest(url: target)
            request.setValue(HTTPClient.defaultUserAgent, forHTTPHeaderField: "User-Agent")
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            guard let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
            return Self.decoded(image)
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        let image = try await task.value
        ImageMemoryCache.shared.insert(image, for: url)
        return image
    }

    func prefetch(_ url: String, headers: [String: String]) {
        Task { _ = try? await image(url, headers: headers) }
    }

    func clear() {
        ImageMemoryCache.shared.removeAll()
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    /// Decodes off the main thread so the first draw does not stall scrolling.
    private nonisolated static func decoded(_ image: UIImage) -> UIImage {
        let width = image.size.width * image.scale
        if width > maxPixelWidth {
            let height = image.size.height * image.scale * maxPixelWidth / width
            if let small = image.preparingThumbnail(of: CGSize(width: maxPixelWidth, height: height.rounded())) { return small }
        }
        return image.preparingForDisplay() ?? image
    }
}
