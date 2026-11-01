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
    var onTap: (CGPoint) -> Void = { _ in }
    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0
    @State private var shown: Bool

    init(page: SourcePage, index: Int, paged: Bool, foreground: Color, onTap: @escaping (CGPoint) -> Void = { _ in }) {
        self.page = page
        self.index = index
        self.paged = paged
        self.foreground = foreground
        self.onTap = onTap
        // A page already in memory draws on its first frame, without a placeholder or fade.
        let cached = ImageMemoryCache.shared[page.url]
        _image = State(initialValue: cached)
        _shown = State(initialValue: cached != nil)
    }

    var body: some View {
        Group {
            if let image {
                Group {
                    if paged {
                        ZoomableImage(image: image, onTap: onTap)
                    } else {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(image.size, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                    }
                }
                .opacity(shown ? 1 : 0)
                .onAppear { withAnimation(.easeOut(duration: 0.2)) { shown = true } }
            } else {
                placeholder
            }
        }
        .task(id: "\(page.url)#\(attempt)") {
            guard image == nil else { return }
            failed = false
            do {
                let loaded = try await ImageLoader.shared.image(page.url, headers: page.headers)
                if loaded.size.height > 0 { PageAspect.known[page.url] = loaded.size.width / loaded.size.height }
                image = loaded
            } catch {
                failed = true
            }
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
                .aspectRatio(PageAspect.known[page.url] ?? PageAspect.guess, contentMode: .fit)
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
