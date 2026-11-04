import SwiftUI
import UIKit

/// How a paged page is first sized (Mihon's "scale type").
enum ReaderScaleType: String, CaseIterable, Identifiable {
    case fitScreen, fitWidth, fitHeight, original, smartFit, stretch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fitScreen: "Fit screen"
        case .fitWidth: "Fit width"
        case .fitHeight: "Fit height"
        case .original: "Original size"
        case .smartFit: "Smart fit"
        case .stretch: "Stretch"
        }
    }
}

/// Where a page larger than the screen starts (Mihon's "zoom start position").
enum ReaderZoomStart: String, CaseIterable, Identifiable {
    case auto, left, right, center

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// What paged modes do with a page wider than it is tall.
enum WidePageMode: String, CaseIterable, Identifiable {
    case off, split, rotate, pan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .split: "Split in two"
        case .rotate: "Rotate to fit"
        case .pan: "Fit height and pan"
        }
    }
}

enum DualPageMode: String, CaseIterable, Identifiable {
    case off, always, landscape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .always: "Always"
        case .landscape: "In landscape"
        }
    }
}

enum ColorFilterMode: String, CaseIterable, Identifiable {
    case normal, multiply, screen, overlay, lighten, darken

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var blendMode: BlendMode {
        switch self {
        case .normal: .normal
        case .multiply: .multiply
        case .screen: .screen
        case .overlay: .overlay
        case .lighten: .lighten
        case .darken: .darken
        }
    }
}

/// The colour filter's colour, stored as one 0xAARRGGBB number.
enum FilterColor {
    static func color(_ argb: Int) -> Color {
        Color(
            .sRGB,
            red: Double((argb >> 16) & 0xFF) / 255,
            green: Double((argb >> 8) & 0xFF) / 255,
            blue: Double(argb & 0xFF) / 255,
            opacity: Double((argb >> 24) & 0xFF) / 255
        )
    }

    static func argb(_ color: Color) -> Int {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return byte(alpha) << 24 | byte(red) << 16 | byte(green) << 8 | byte(blue)
    }
}

/// Rotation while reading, chosen per series with a default (Mihon's "rotation type").
enum ReaderOrientation: String, CaseIterable, Identifiable {
    /// Follows the device.
    case free, portrait, landscape
    /// Keeps whichever way the device was held when the reader opened.
    case locked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: "Free"
        case .portrait: "Portrait"
        case .landscape: "Landscape"
        case .locked: "Lock current"
        }
    }

    private static func key(_ mangaKey: String) -> String { "reader.orientation\n" + mangaKey }

    static var preferred: ReaderOrientation {
        get { ReaderOrientation(rawValue: Pref.readerOrientation.value()) ?? .free }
        set { Pref.readerOrientation.set(newValue.rawValue) }
    }

    static func load(for mangaKey: String) -> ReaderOrientation {
        UserDefaults.standard.string(forKey: key(mangaKey)).flatMap(ReaderOrientation.init) ?? preferred
    }

    func save(for mangaKey: String) { UserDefaults.standard.set(rawValue, forKey: Self.key(mangaKey)) }

    /// The orientations allowed while reading; `current` is how the screen is turned now.
    func mask(current: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
        switch self {
        case .free: return .all
        case .portrait: return .portrait
        case .landscape: return .landscape
        case .locked:
            switch current {
            case .portrait: return .portrait
            case .portraitUpsideDown: return .portraitUpsideDown
            case .landscapeLeft: return .landscapeLeft
            case .landscapeRight: return .landscapeRight
            default: return .all
            }
        }
    }
}

/// The orientations the app allows, read by `AppDelegate`. The reader narrows it and puts it back on close.
enum OrientationLock {
    nonisolated(unsafe) static var mask: UIInterfaceOrientationMask = .all

    @MainActor
    static func apply(_ mask: UIInterfaceOrientationMask) {
        self.mask = mask
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                var controller = window.rootViewController
                while let current = controller {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = current.presentedViewController
                }
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
    }

    /// How the foreground scene is turned now.
    @MainActor
    static var current: UIInterfaceOrientation {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.interfaceOrientation ?? .unknown
    }
}
