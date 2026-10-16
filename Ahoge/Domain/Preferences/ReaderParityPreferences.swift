// Native adaptation of stable Mihon reader behavior.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import Foundation

// Native equivalents of the stable Mihon reader options. Source coordinates stay unchanged.
enum ReaderScale: String, Codable, CaseIterable, Identifiable {
    case fitScreen, fitWidth, fitHeight, original, smartFit
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fitScreen: return "Fit screen"
        case .fitWidth: return "Fit width"
        case .fitHeight: return "Fit height"
        case .original: return "Original size"
        case .smartFit: return "Smart fit"
        }
    }
}
enum ReaderZoomStart: String, Codable, CaseIterable, Identifiable {
    case automatic, left, right, center
    var id: String { rawValue }
}
enum ReaderBackground: String, Codable, CaseIterable, Identifiable {
    case black, white, gray, automatic
    var id: String { rawValue }
}
enum ReaderTapNavigation: String, Codable, CaseIterable, Identifiable {
    case standard, edges, vertical, lShape, kindle, disabled
    var id: String { rawValue }
}
enum ReaderNavigationAction: Equatable { case forward, backward, menu }
extension ReaderTapNavigation {
    var title: String {
        switch self {
        case .standard: return "Default"
        case .edges: return "Edge"
        case .vertical: return "Top and bottom"
        case .lShape: return "L shaped"
        case .kindle: return "Kindle"
        case .disabled: return "Disabled"
        }
    }
    func action(x: Double, y: Double, rtl: Bool, verticalDefault: Bool,
                invertHorizontal: Bool, invertVertical: Bool) -> ReaderNavigationAction {
        let x = invertHorizontal ? 1 - x : x
        let y = invertVertical ? 1 - y : y
        switch self {
        case .disabled: return .menu
        case .standard:
            if verticalDefault { return ReaderTapNavigation.lShape.action(x: x, y: y, rtl: rtl, verticalDefault: false, invertHorizontal: false, invertVertical: false) }
            if x < 0.33 { return rtl ? .forward : .backward }
            if x >= 0.66 { return rtl ? .backward : .forward }
            return .menu
        case .vertical:
            if y < 0.33 { return .backward }
            if y >= 0.66 { return .forward }
            return .menu
        case .lShape:
            if y < 0.33 || (y < 0.66 && x < 0.33) { return .backward }
            if y >= 0.66 || x >= 0.66 { return .forward }
            return .menu
        case .kindle:
            if y < 0.33 { return .menu }
            return x < 0.33 ? .backward : .forward
        case .edges:
            if x < 0.33 || x >= 0.66 { return .forward }
            if y >= 0.66 { return .backward }
            return .menu
        }
    }
}
enum ReaderDualPageDisplay: String, Codable, CaseIterable, Identifiable {
    case never, always, wide
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}
struct ReaderParityPreferences: Codable, Hashable {
    var dualPageDisplay: ReaderDualPageDisplay = .never
    var firstPageAlone = true
    var scale: ReaderScale = .fitScreen
    var zoomStart: ReaderZoomStart = .automatic
    var tapNavigation: ReaderTapNavigation = .standard
    var invertHorizontalTaps = false
    var invertVerticalTaps = false
    var animatePages = true
    var background: ReaderBackground = .black
    var cropBorders = false
    var invertSplitOrder = false
    var rotateWidePages = false
    var rotateClockwise = true
    var continuousGap: Double = 12
    var webtoonGap: Double = 0
    var sidePadding: Double = 0
    var doubleTapZoom = true
    var allowZoomOut = false
    var fullscreen = true
    static let `default` = ReaderParityPreferences()
    enum CodingKeys: String, CodingKey {
        case dualPageDisplay, firstPageAlone
        case scale, zoomStart, tapNavigation, invertHorizontalTaps, invertVerticalTaps
        case animatePages, background, cropBorders, invertSplitOrder, rotateWidePages, rotateClockwise
        case continuousGap, webtoonGap, sidePadding, doubleTapZoom, allowZoomOut, fullscreen
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dualPageDisplay = try c.decodeIfPresent(ReaderDualPageDisplay.self, forKey: .dualPageDisplay) ?? .never
        firstPageAlone = try c.decodeIfPresent(Bool.self, forKey: .firstPageAlone) ?? true
        scale = try c.decodeIfPresent(ReaderScale.self, forKey: .scale) ?? .fitScreen
        zoomStart = try c.decodeIfPresent(ReaderZoomStart.self, forKey: .zoomStart) ?? .automatic
        tapNavigation = try c.decodeIfPresent(ReaderTapNavigation.self, forKey: .tapNavigation) ?? .standard
        invertHorizontalTaps = try c.decodeIfPresent(Bool.self, forKey: .invertHorizontalTaps) ?? false
        invertVerticalTaps = try c.decodeIfPresent(Bool.self, forKey: .invertVerticalTaps) ?? false
        animatePages = try c.decodeIfPresent(Bool.self, forKey: .animatePages) ?? true
        background = try c.decodeIfPresent(ReaderBackground.self, forKey: .background) ?? .black
        cropBorders = try c.decodeIfPresent(Bool.self, forKey: .cropBorders) ?? false
        invertSplitOrder = try c.decodeIfPresent(Bool.self, forKey: .invertSplitOrder) ?? false
        rotateWidePages = try c.decodeIfPresent(Bool.self, forKey: .rotateWidePages) ?? false
        rotateClockwise = try c.decodeIfPresent(Bool.self, forKey: .rotateClockwise) ?? true
        continuousGap = min(max(try c.decodeIfPresent(Double.self, forKey: .continuousGap) ?? 12, 0), 64)
        webtoonGap = min(max(try c.decodeIfPresent(Double.self, forKey: .webtoonGap) ?? 0, 0), 64)
        sidePadding = min(max(try c.decodeIfPresent(Double.self, forKey: .sidePadding) ?? 0, 0), 25)
        doubleTapZoom = try c.decodeIfPresent(Bool.self, forKey: .doubleTapZoom) ?? true
        allowZoomOut = try c.decodeIfPresent(Bool.self, forKey: .allowZoomOut) ?? false
        fullscreen = try c.decodeIfPresent(Bool.self, forKey: .fullscreen) ?? true
    }
}
