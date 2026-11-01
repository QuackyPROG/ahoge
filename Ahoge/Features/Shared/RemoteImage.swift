import SwiftUI

struct RemoteImage: View {
    let url: String
    var headers: [String: String] = [:]
    @State private var image: UIImage?
    @State private var failed = false

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
            image = nil
            failed = false
            guard !url.isEmpty else {
                failed = true
                return
            }
            do {
                image = try await ImageLoader.shared.image(url, headers: headers)
            } catch {
                failed = true
            }
        }
    }
}
