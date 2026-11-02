import SwiftUI

struct RemoteImage: View {
    let url: String
    var headers: [String: String] = [:]
    /// Decode no wider than this many pixels; covers in grids pass a small value.
    var maxPixelWidth: CGFloat = ImageLoader.maxPixelWidth
    @State private var image: UIImage?
    @State private var failed = false

    init(url: String, headers: [String: String] = [:], maxPixelWidth: CGFloat = ImageLoader.maxPixelWidth) {
        self.url = url
        self.headers = headers
        self.maxPixelWidth = maxPixelWidth
        // A cover already in memory draws at once, so scrolling back shows no placeholder.
        _image = State(initialValue: ImageMemoryCache.shared[ImageLoader.cacheKey(url, maxPixelWidth: maxPixelWidth)])
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                Image(systemName: "photo").foregroundStyle(.secondary)
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .task(id: url) {
            let key = ImageLoader.cacheKey(url, maxPixelWidth: maxPixelWidth)
            if let hit = ImageMemoryCache.shared[key] {
                image = hit
                failed = false
                return
            }
            image = nil
            failed = false
            guard !url.isEmpty else {
                failed = true
                return
            }
            do {
                let loaded = try await ImageLoader.shared.image(url, headers: headers, maxPixelWidth: maxPixelWidth)
                withAnimation(.easeOut(duration: 0.18)) { image = loaded }
            } catch {
                failed = true
            }
        }
    }
}
