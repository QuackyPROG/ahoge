import UIKit

/// Loads images with per-request headers (Referer), memory and disk cached, de-duplicated.
actor ImageLoader {
    static let shared = ImageLoader()

    private let session: URLSession
    private let memory = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage, Error>] = [:]

    init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 50 << 20, diskCapacity: 500 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpCookieStorage = .shared
        session = URLSession(configuration: config)
        memory.totalCostLimit = 200 << 20
    }

    func image(_ url: String, headers: [String: String] = [:]) async throws -> UIImage {
        if let hit = memory.object(forKey: url as NSString) { return hit }
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
            guard let image = UIImage(data: data)?.preparingForDisplay() ?? UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            return image
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        let image = try await task.value
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        memory.setObject(image, forKey: url as NSString, cost: cost)
        return image
    }

    func prefetch(_ url: String, headers: [String: String]) {
        Task { _ = try? await image(url, headers: headers) }
    }

    func clear() {
        memory.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
    }
}
