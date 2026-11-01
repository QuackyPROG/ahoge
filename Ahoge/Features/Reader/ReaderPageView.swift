import SwiftUI

struct ReaderPageView: View {
    let page: SourcePage
    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(image.size, contentMode: .fit)
                    .frame(maxWidth: .infinity)
            } else if failed {
                VStack(spacing: 10) {
                    Text("Couldn't load this page").foregroundStyle(.secondary)
                    Button("Retry") { attempt += 1 }.buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, minHeight: 400)
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, minHeight: 600)
            }
        }
        .task(id: "\(page.url)#\(attempt)") {
            failed = false
            do {
                image = try await ImageLoader.shared.image(page.url, headers: page.headers)
            } catch {
                failed = true
            }
        }
    }
}
