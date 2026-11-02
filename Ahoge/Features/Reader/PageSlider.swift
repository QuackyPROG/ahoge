import SwiftUI

/// Where pages sit on the scrubber track. Pure, so it is unit tested.
enum PageSliderMath {
    /// Space either side, so the thumb's centre reaches the first and last page unclipped.
    static let inset: CGFloat = 10
    static let maxDot: CGFloat = 4
    /// Closer than this, dots merge into a line and are not drawn.
    static let minSpacing: CGFloat = 3

    static func offset(page: Int, count: Int, width: CGFloat, reversed: Bool) -> CGFloat {
        guard count > 1 else { return reversed ? width - inset : inset }
        let track = max(width - inset * 2, 0)
        let fraction = CGFloat(min(max(page, 0), count - 1)) / CGFloat(count - 1)
        let along = inset + track * fraction
        return reversed ? width - along : along
    }

    static func page(at x: CGFloat, count: Int, width: CGFloat, reversed: Bool) -> Int {
        guard count > 1 else { return 0 }
        let track = max(width - inset * 2, 1)
        let along = reversed ? width - x : x
        let fraction = min(max((along - inset) / track, 0), 1)
        return Int((fraction * CGFloat(count - 1)).rounded())
    }

    static func spacing(count: Int, width: CGFloat) -> CGFloat {
        count > 1 ? max(width - inset * 2, 0) / CGFloat(count - 1) : 0
    }

    static func showsDots(count: Int, width: CGFloat) -> Bool {
        count > 1 && spacing(count: count, width: width) >= minSpacing
    }

    static func dotSize(count: Int, width: CGFloat) -> CGFloat {
        min(maxDot, spacing(count: count, width: width) / 2)
    }
}

/// The reader's page scrubber, like Mihon's: a dot per page, the read part filled, the page
/// number above the thumb while dragging, and a haptic tick each time the page changes.
struct PageSlider: View {
    @Binding var page: Int
    let count: Int
    /// Mirrors the track, for right-to-left reading.
    var reversed = false
    var onEditingChanged: (Bool) -> Void = { _ in }

    /// Reset by SwiftUI when the gesture ends or is cancelled, so it can never stick.
    @GestureState private var dragging = false
    @State private var reportedEditing = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let midY = geometry.size.height / 2
            let x = PageSliderMath.offset(page: page, count: count, width: width, reversed: reversed)
            ZStack {
                Capsule()
                    .fill(.white.opacity(0.22))
                    .frame(height: 4)
                Capsule()
                    .fill(.white)
                    .frame(width: reversed ? width - x : x, height: 4)
                    .frame(maxWidth: .infinity, alignment: reversed ? .trailing : .leading)
                if PageSliderMath.showsDots(count: count, width: width) {
                    let size = PageSliderMath.dotSize(count: count, width: width)
                    ForEach(0..<count, id: \.self) { index in
                        Circle()
                            .fill(index <= page ? Color.black.opacity(0.45) : Color.white.opacity(0.75))
                            .frame(width: size, height: size)
                            .position(x: PageSliderMath.offset(page: index, count: count, width: width, reversed: reversed), y: midY)
                    }
                }
                Circle()
                    .fill(.white)
                    .frame(width: dragging ? 26 : 20, height: dragging ? 26 : 20)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .position(x: x, y: midY)
                if dragging {
                    Text("\(page + 1)")
                        .font(.footnote.weight(.bold).monospacedDigit())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.white, in: Capsule())
                        .position(x: x, y: midY - 30)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($dragging) { _, state, _ in state = true }
                    .onChanged { value in
                        let target = PageSliderMath.page(at: value.location.x, count: count, width: width, reversed: reversed)
                        if target != page { page = target }
                    }
            )
            .animation(.spring(duration: 0.2), value: dragging)
        }
        .onChange(of: dragging) { _, isDragging in
            reportedEditing = isDragging
            onEditingChanged(isDragging)
        }
        .onDisappear {
            if reportedEditing {
                reportedEditing = false
                onEditingChanged(false)
            }
        }
        .sensoryFeedback(.selection, trigger: page) { _, _ in dragging }
        .frame(height: 32)
        // Drawn by offsets; mirroring is done by `reversed`, never by the layout direction.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement()
        .accessibilityLabel("Page")
        .accessibilityValue("\(min(page, count - 1) + 1) of \(count)")
        .accessibilityAdjustableAction { direction in
            let target: Int
            switch direction {
            case .increment: target = min(page + 1, count - 1)
            case .decrement: target = max(page - 1, 0)
            @unknown default: return
            }
            guard target != page else { return }
            onEditingChanged(true)
            page = target
            onEditingChanged(false)
        }
    }
}
