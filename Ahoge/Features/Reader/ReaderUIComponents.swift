// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

//
//  ReaderUIComponents.swift
//  Ahoge
//

import SwiftUI

struct ReaderChromeButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
    }
}

struct ReaderPagedContainer<Content: View>: View {
    @Binding var currentIndex: Int
    let itemCount: Int
    let pageWidth: CGFloat
    var vertical: Bool = false
    var animatePages: Bool = true
    let allowsInteractivePaging: Bool
    let shouldCaptureDrag: (CGFloat, CGFloat) -> Bool
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat, CGFloat, CGFloat) -> Void
    let onDragCancelled: () -> Void
    @ViewBuilder let content: Content

    @GestureState private var dragTranslation: CGFloat = 0
    @GestureState private var gestureActive = false
    @State private var capturedDrag = false

    var body: some View {
        GeometryReader { _ in
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .offset(x: vertical ? 0 : -CGFloat(currentIndex) * pageWidth + (allowsInteractivePaging ? dragTranslation : 0),
                        y: vertical ? -CGFloat(currentIndex) * pageWidth + (allowsInteractivePaging ? dragTranslation : 0) : 0)
                .animation(animatePages ? .interactiveSpring(response: 0.28, dampingFraction: 0.9) : nil, value: currentIndex)
                .contentShape(Rectangle())
                .clipped()
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12, coordinateSpace: .local)
                        .updating($gestureActive) { _, active, _ in active = true }
                        .updating($dragTranslation) { value, state, _ in
                            guard shouldCaptureDrag(vertical ? value.translation.height : value.translation.width, vertical ? value.translation.width : value.translation.height) else { return }
                            state = allowsInteractivePaging ? (vertical ? value.translation.height : value.translation.width) : 0
                        }
                        .onChanged { value in
                            guard shouldCaptureDrag(vertical ? value.translation.height : value.translation.width, vertical ? value.translation.width : value.translation.height) else { return }
                            capturedDrag = true
                            onDragChanged(vertical ? value.translation.height : value.translation.width)
                        }
                        .onEnded { value in
                            let wasCaptured = capturedDrag
                            capturedDrag = false
                            guard wasCaptured else { return }
                            guard shouldCaptureDrag(vertical ? value.translation.height : value.translation.width, vertical ? value.translation.width : value.translation.height) else {
                                onDragCancelled()
                                return
                            }
                            onDragChanged(0)
                            onDragEnded(vertical ? value.translation.height : value.translation.width, vertical ? value.predictedEndTranslation.height : value.predictedEndTranslation.width, pageWidth)
                        }
                )
                .onChange(of: gestureActive) { _, active in
                    if !active, capturedDrag {
                        capturedDrag = false
                        onDragCancelled()
                    }
                }
                .onDisappear {
                    if capturedDrag { capturedDrag = false; onDragCancelled() }
                }
        }
    }
}

struct ReaderTransitionPage: View {
    let title: String
    let chapterTitle: String?
    let systemImage: String
    let isEnabled: Bool
    let progress: CGFloat
    let isLoading: Bool
    let confirmLabel: String
    let action: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: isLoading ? "arrow.triangle.2.circlepath" : systemImage)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white.opacity(isEnabled ? 0.9 : 0.35))
                    .rotationEffect(.degrees(isLoading ? 360 : 0))
                    .animation(isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isLoading)

                VStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.45))
                    
                    Text(chapterTitle ?? "No chapter available")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(isEnabled ? 0.72 : 0.3))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                if !isLoading {
                    ProgressView(value: progress, total: 1)
                        .tint(.white)
                        .opacity(isEnabled ? 1 : 0.25)
                        .frame(maxWidth: 180)
                        .scaleEffect(x: 1, y: progress > 0 ? 1 : 0.1, anchor: .center)
                }

                Button(isLoading ? "Loading…" : confirmLabel, action: action)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isEnabled || isLoading)
                    .tint(.white.opacity(isEnabled ? 0.18 : 0.08))
                    .opacity(isEnabled ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .opacity(isEnabled ? 0.4 + (0.6 * Double(progress)) : 0.4)
            .scaleEffect(isEnabled ? 0.95 + (0.05 * Double(progress)) : 0.95)
            .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.8, blendDuration: 0.1), value: progress)
        }
    }
}

struct ReaderBottomPill: View {
    let systemImage: String
    let title: String
    var isProminent: Bool = false
    var foregroundColor: Color = .white
    var backgroundTint: Color = .white
    var regularBackgroundOpacity: Double = 0.08
    var prominentBackgroundOpacity: Double = 0.18
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.headline)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 60)
            .padding(.vertical, 8)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var backgroundStyle: some ShapeStyle {
        if isProminent {
            return AnyShapeStyle(backgroundTint.opacity(prominentBackgroundOpacity))
        }
        return AnyShapeStyle(backgroundTint.opacity(regularBackgroundOpacity))
    }
}

struct ReaderVisiblePageFramesPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

enum ReaderTapZone {
    case topLeading
    case topCenter
    case topTrailing
    case middleLeading
    case center
    case middleTrailing
    case bottomLeading
    case bottomCenter
    case bottomTrailing

    static func resolve(point: CGPoint, in size: CGSize) -> ReaderTapZone {
        let column = min(max(Int((point.x / max(size.width, 1)) * 3), 0), 2)
        let row = min(max(Int((point.y / max(size.height, 1)) * 3), 0), 2)
        switch (row, column) {
        case (0, 0): return .topLeading
        case (0, 1): return .topCenter
        case (0, 2): return .topTrailing
        case (1, 0): return .middleLeading
        case (1, 1): return .center
        case (1, 2): return .middleTrailing
        case (2, 0): return .bottomLeading
        case (2, 1): return .bottomCenter
        default: return .bottomTrailing
        }
    }

    func intent(isRTLPager: Bool) -> ReaderTapIntent {
        switch self {
        case .center:
            return .toggleChrome
        case .topCenter, .bottomCenter:
            return .none
        case .topLeading, .middleLeading, .bottomLeading:
            return isRTLPager ? .forward : .backward
        case .topTrailing, .middleTrailing, .bottomTrailing:
            return isRTLPager ? .backward : .forward
        }
    }
}

enum ReaderTapIntent {
    case forward
    case backward
    case toggleChrome
    case none
}

enum ReaderTransitionDirection {
    case previous
    case next
}

struct ReaderTransitionState: Equatable {
    static let activationDistance: CGFloat = 120

    let direction: ReaderTransitionDirection
    let progress: CGFloat
    let isLoading: Bool
}

struct ReaderEmptyState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle)
                .accessibilityHidden(true)
                .foregroundStyle(.white.opacity(0.7))
            Text("Chapter could not be displayed")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button("Retry chapter", action: retry)
                .frame(minHeight: 44)
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.18))
        }
            }
            .padding(.vertical, 32)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
    }
}

struct ReaderPageStack<Content: View>: View {
    let vertical: Bool
    @ViewBuilder let content: Content
    var body: some View {
        if vertical { VStack(spacing: 0) { content } }
        else { HStack(spacing: 0) { content } }
    }
}

struct ReaderFullscreenPresentation: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.ignoresSafeArea() } else { content }
    }
}

// Native phases include outer-scroll tracking, drag, deceleration and programmatic
// ScrollViewReader animation. Captured identities prevent old containers releasing
// replacement ownership. This uses the same reducer as image surfaces.
struct ReaderContinuousScrollLifecycle: ViewModifier {
    let epoch: UUID
    let onEvent: (ReaderSurfaceIdentity, ReaderSurfaceEvent) -> Void
    @State private var host = UUID()

    func body(content: Content) -> some View {
        let identity = ReaderSurfaceIdentity(epoch: epoch, member: ReaderSurfaceVisibility.continuousScrollMember,
            host: host, generation: 0)
        content
            .onAppear { onEvent(identity, .register) }
            .onScrollPhaseChange { _, phase in
                let observed: ReaderContinuousScrollPhase
                switch phase {
                case .idle: observed = .idle
                case .tracking: observed = .tracking
                case .interacting: observed = .interacting
                case .decelerating: observed = .decelerating
                case .animating: observed = .animating
                @unknown default: observed = .tracking
                }
                // A programmatic initial scroll may report its phase before
                // onAppear. Repeated registration is idempotent; retired/old
                // identities are still rejected by the production reducer.
                onEvent(identity, .register)
                onEvent(identity, observed.event)
            }
            .onDisappear {
                onEvent(identity, .retire)
                host = UUID() // A later appearance is a fresh mount, never a retired token.
            }
    }
}
