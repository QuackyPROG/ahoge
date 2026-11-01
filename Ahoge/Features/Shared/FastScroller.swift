import SwiftUI

/// Tracks which rows of a long list are on screen, so a fast scroller knows where the list is.
@MainActor
final class VisibleRows: ObservableObject {
    @Published private(set) var top = 0
    private var visible = Set<Int>()

    func appeared(_ index: Int) {
        visible.insert(index)
        update()
    }

    func disappeared(_ index: Int) {
        visible.remove(index)
        update()
    }

    private func update() {
        if let first = visible.min(), first != top { top = first }
    }
}

/// Mihon-style fast scroller: a thumb on the right edge that can be dragged through a long list,
/// with a bubble naming the row it will land on.
struct FastScroller: View {
    let count: Int
    /// The row at the top of the screen, for placing the thumb while not dragging.
    let topIndex: Int
    let label: (Int) -> String
    let scrollTo: (Int) -> Void

    @State private var dragIndex: Int?
    private let thumbHeight: CGFloat = 44

    var body: some View {
        GeometryReader { geometry in
            let track = max(geometry.size.height - thumbHeight, 1)
            let index = dragIndex ?? topIndex
            let fraction = count > 1 ? CGFloat(index) / CGFloat(count - 1) : 0
            let y = min(max(fraction, 0), 1) * track
            ZStack(alignment: .topTrailing) {
                Color.clear
                if let dragIndex {
                    Text(label(dragIndex))
                        .font(.subheadline.bold())
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(radius: 4)
                        .offset(x: -36, y: y + thumbHeight / 2 - 18)
                        .transition(.opacity)
                }
                Capsule()
                    .fill(dragIndex == nil ? Color.secondary.opacity(0.55) : Color.accentColor)
                    .frame(width: dragIndex == nil ? 5 : 8, height: thumbHeight)
                    .frame(width: 28, height: thumbHeight)
                    .contentShape(Rectangle())
                    .offset(y: y)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("track"))
                            .onChanged { value in
                                let position = min(max((value.location.y - thumbHeight / 2) / track, 0), 1)
                                guard count > 1 else { return }
                                let target = Int((position * CGFloat(count - 1)).rounded())
                                if target != dragIndex {
                                    dragIndex = target
                                    scrollTo(target)
                                }
                            }
                            .onEnded { _ in withAnimation(.easeOut(duration: 0.2)) { dragIndex = nil } }
                    )
                    .accessibilityLabel("Fast scroll")
            }
            .coordinateSpace(name: "track")
            .animation(.easeOut(duration: 0.15), value: dragIndex == nil)
        }
        .frame(width: 28)
        .padding(.vertical, 8)
    }
}
