import SwiftUI

/// Width over height of pages already seen, so a page that scrolls back in keeps its height
/// while it reloads and the strip does not jump. Only read and written from views.
enum PageAspect {
    static var known: [String: CGFloat] = [:]
    /// A typical page, until the real one is known.
    static let guess: CGFloat = 0.7
}

struct ReaderPageView: View {
    let page: SourcePage
    let index: Int
    let paged: Bool
    let foreground: Color
    let transform: ImageTransform
    let zoom: ZoomOptions
    var onTap: (CGPoint) -> Void = { _ in }
    /// Told the page's untransformed size once known, so wide pages can be split or kept alone.
    var onSize: (CGSize) -> Void = { _ in }
    @State private var image: UIImage?
    /// The cache key `image` was loaded for; a new transform loads again.
    @State private var loadedKey: String?
    @State private var failed = false
    @State private var attempt = 0
    @State private var shown: Bool
    @State private var saveError: String?

    init(
        page: SourcePage, index: Int, paged: Bool, foreground: Color,
        transform: ImageTransform = .plain, zoom: ZoomOptions = ZoomOptions(),
        onTap: @escaping (CGPoint) -> Void = { _ in }, onSize: @escaping (CGSize) -> Void = { _ in }
    ) {
        self.page = page
        self.index = index
        self.paged = paged
        self.foreground = foreground
        self.transform = transform
        self.zoom = zoom
        self.onTap = onTap
        self.onSize = onSize
        // A page already in memory draws on its first frame, without a placeholder or fade.
        let key = ImageLoader.cacheKey(page.url, maxPixelWidth: ImageLoader.maxPixelWidth, transform: transform)
        let cached = ImageMemoryCache.shared[key]
        _image = State(initialValue: cached)
        _loadedKey = State(initialValue: cached == nil ? nil : key)
        _shown = State(initialValue: cached != nil)
    }

    private var cacheKey: String { ImageLoader.cacheKey(page.url, maxPixelWidth: ImageLoader.maxPixelWidth, transform: transform) }

    var body: some View {
        Group {
            if let image {
                Group {
                    if paged {
                        ZoomableImage(image: image, options: zoom, onTap: onTap)
                    } else {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(image.size, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                    }
                }
                .opacity(shown ? 1 : 0)
                .onAppear { withAnimation(.easeOut(duration: 0.2)) { shown = true } }
                .contextMenu { pageMenu(image) }
            } else {
                placeholder
            }
        }
        .alert("Couldn't save page", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .task(id: "\(cacheKey)#\(attempt)") {
            let key = cacheKey
            if let plain = ImageMemoryCache.shared[page.url] { onSize(plain.size) }
            guard image == nil || loadedKey != key else { return }
            failed = false
            do {
                let loaded = try await ImageLoader.shared.image(page.url, headers: page.headers, transform: transform)
                if loaded.size.height > 0 { PageAspect.known[key] = loaded.size.width / loaded.size.height }
                if let plain = ImageMemoryCache.shared[page.url] { onSize(plain.size) }
                image = loaded
                loadedKey = key
            } catch {
                failed = true
            }
        }
    }

    @ViewBuilder private func pageMenu(_ image: UIImage) -> some View {
        let preview = Image(uiImage: image)
        Button("Save to Photos", systemImage: "square.and.arrow.down") {
            Task {
                do { try await PhotoSaver.save(image) } catch { saveError = error.localizedDescription }
            }
        }
        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.image = image }
        ShareLink(item: preview, preview: SharePreview("Page \(index + 1)", image: preview)) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }

    @ViewBuilder private var placeholder: some View {
        if paged {
            placeholderContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                // There is no zoom view yet to report taps.
                .onTapGesture { onTap(CGPoint(x: 0.5, y: 0.5)) }
        } else {
            placeholderContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(PageAspect.known[cacheKey] ?? PageAspect.guess, contentMode: .fit)
        }
    }

    private var placeholderContent: some View {
        VStack(spacing: 14) {
            if failed {
                Image(systemName: "exclamationmark.triangle").font(.title2)
                Text("Couldn't load page \(index + 1)").font(.subheadline)
                Button("Retry") { attempt += 1 }
                    .buttonStyle(.bordered)
                    .tint(foreground)
            } else {
                Text("\(index + 1)").font(.title.weight(.semibold).monospacedDigit())
                ProgressView().tint(foreground)
            }
        }
        .foregroundStyle(foreground.opacity(0.7))
    }
}

/// The card between chapters (Mihon's chapter transition): what was finished and what is next.
struct ReaderTransitionView: View {
    let item: ReaderModel.Item
    let foreground: Color
    let isLoadingNext: Bool
    let error: Error?
    let openPrevious: (ChapterRecord) -> Void
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch item.kind {
            case .start(let previous):
                if let previous {
                    line("Previous", previous.name)
                    line("Current", item.chapter.name)
                    Button { openPrevious(previous) } label: { Label("Read previous chapter", systemImage: "chevron.up") }
                        .buttonStyle(.bordered)
                        .tint(foreground)
                } else {
                    line("Current", item.chapter.name)
                    Text("There's no previous chapter").font(.subheadline).foregroundStyle(foreground.opacity(0.6))
                }
            case .end(let next):
                line("Finished", item.chapter.name)
                if let next {
                    line("Next", next.name)
                    if let error {
                        Text(error.localizedDescription).font(.footnote).foregroundStyle(foreground.opacity(0.6))
                        Button("Retry", action: retry).buttonStyle(.bordered).tint(foreground)
                    } else if isLoadingNext {
                        ProgressView().tint(foreground)
                    }
                } else {
                    Text("There's no next chapter").font(.subheadline).foregroundStyle(foreground.opacity(0.6))
                }
            case .page:
                EmptyView()
            }
        }
        .foregroundStyle(foreground)
        .frame(maxWidth: 420, alignment: .leading)
        .padding(.horizontal, 32)
        .padding(.vertical, 56)
        .frame(maxWidth: .infinity)
    }

    private func line(_ label: String, _ name: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(foreground.opacity(0.55))
            Text(name).font(.headline).lineLimit(3)
        }
    }
}
