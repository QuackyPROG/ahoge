import SwiftUI

/// What a tap on a paged page does.
enum TapAction: Equatable {
    case previous, next, menu
}

/// Where taps turn pages (Mihon's "tap zones"). Regions are in unit coordinates, origin at the top
/// left, for left-to-right reading; anything outside them opens the menu.
enum TapZoneLayout: String, CaseIterable, Identifiable {
    /// Mihon's default "L shaped": top and left back, bottom and right on, the middle for the menu.
    case standard
    case kindle, edge, rightAndLeft, disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Default (L shaped)"
        case .kindle: "Kindle-ish"
        case .edge: "Edge"
        case .rightAndLeft: "Right and left"
        case .disabled: "Disabled"
        }
    }

    var regions: [(rect: CGRect, action: TapAction)] {
        let third: CGFloat = 1 / 3, twoThirds: CGFloat = 2 / 3
        switch self {
        case .standard:
            return [
                (CGRect(x: 0, y: 0, width: 1, height: third), .previous),
                (CGRect(x: 0, y: third, width: third, height: third), .previous),
                (CGRect(x: twoThirds, y: third, width: third, height: third), .next),
                (CGRect(x: 0, y: twoThirds, width: 1, height: third), .next),
            ]
        case .kindle:
            return [
                (CGRect(x: 0, y: third, width: third, height: twoThirds), .previous),
                (CGRect(x: third, y: third, width: twoThirds, height: twoThirds), .next),
            ]
        case .edge:
            return [
                (CGRect(x: 0, y: 0, width: third, height: 1), .next),
                (CGRect(x: twoThirds, y: 0, width: third, height: 1), .next),
                (CGRect(x: third, y: twoThirds, width: third, height: third), .previous),
            ]
        case .rightAndLeft:
            return [
                (CGRect(x: 0, y: 0, width: third, height: 1), .previous),
                (CGRect(x: twoThirds, y: 0, width: third, height: 1), .next),
            ]
        case .disabled:
            return []
        }
    }
}

enum TapZones {
    /// The action for a tap at `point` on a page of `size`. `inverted` swaps back and on.
    static func action(at point: CGPoint, size: CGSize, layout: TapZoneLayout, inverted: Bool) -> TapAction {
        guard size.width > 0, size.height > 0 else { return .menu }
        // Clamped so a tap on the far edge still lands in the last region.
        let unit = CGPoint(x: min(max(point.x / size.width, 0), 0.999), y: min(max(point.y / size.height, 0), 0.999))
        guard let region = layout.regions.first(where: { $0.rect.contains(unit) }) else { return .menu }
        guard inverted else { return region.action }
        switch region.action {
        case .previous: return .next
        case .next: return .previous
        case .menu: return .menu
        }
    }
}

/// The tap zones drawn over the page for a moment when the reader opens.
struct TapZoneOverlay: View {
    let layout: TapZoneLayout
    /// Right to left: the zones are mirrored, as taps are.
    let mirrored: Bool
    let inverted: Bool

    var body: some View {
        GeometryReader { geometry in
            let regions = layout.regions
            ForEach(regions.indices, id: \.self) { index in
                let rect = mirrored ? CGRect(x: 1 - regions[index].rect.maxX, y: regions[index].rect.minY, width: regions[index].rect.width, height: regions[index].rect.height) : regions[index].rect
                let action = TapZones.action(at: CGPoint(x: regions[index].rect.midX, y: regions[index].rect.midY), size: CGSize(width: 1, height: 1), layout: layout, inverted: inverted)
                Rectangle()
                    .fill((action == .next ? Color.green : Color.red).opacity(0.3))
                    .overlay {
                        Text(action == .next ? "Next" : "Previous")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: rect.width * geometry.size.width, height: rect.height * geometry.size.height)
                    .position(x: rect.midX * geometry.size.width, y: rect.midY * geometry.size.height)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
