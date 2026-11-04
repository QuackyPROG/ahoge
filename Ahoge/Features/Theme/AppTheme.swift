import SwiftUI
import UIKit

/// One color as its light and dark mode values (0xRRGGBB), the way Mihon's color schemes list them.
struct Swatch: Equatable {
    let light: UInt32
    let dark: UInt32

    init(_ light: UInt32, _ dark: UInt32) {
        self.light = light
        self.dark = dark
    }

    /// Follows the light/dark appearance by itself.
    var color: Color {
        let light = UIColor(rgb: light)
        let dark = UIColor(rgb: dark)
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

/// The app's colors, named after the Material 3 roles Mihon uses.
struct Palette: Equatable {
    /// Accent: buttons, selection, badges.
    var primary: Swatch
    /// Text and icons drawn on `primary`.
    var onPrimary: Swatch
    /// Quiet accent fill: counts, chips, selected rows.
    var container: Swatch
    var background: Swatch
    /// Cards, grouped rows, sheets.
    var surface: Swatch
    var onSurface: Swatch
    var onSurfaceVariant: Swatch
    var outline: Swatch
}

/// Mihon's app themes that have fixed colors (Monet needs Android wallpaper colors).
enum AppTheme: String, CaseIterable, Identifiable {
    case standard, greenApple, lavender, midnightDusk, strawberryDaiquiri, tako

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Default"
        case .greenApple: "Green Apple"
        case .lavender: "Lavender"
        case .midnightDusk: "Midnight Dusk"
        case .strawberryDaiquiri: "Strawberry Daiquiri"
        case .tako: "Tako"
        }
    }

    func palette(pureBlack: Bool) -> Palette {
        var palette = base
        if pureBlack {
            palette.background = Swatch(palette.background.light, 0x000000)
            palette.surface = Swatch(palette.surface.light, 0x0C0C0C)
        }
        return palette
    }

    // Values are Mihon's (light, dark): primary, onPrimary, secondaryContainer, background,
    // surfaceContainer, onSurface, onSurfaceVariant, outline.
    private var base: Palette {
        switch self {
        case .standard:
            Palette(primary: Swatch(0x0058CA, 0xB0C6FF), onPrimary: Swatch(0xFFFFFF, 0x002D6E), container: Swatch(0xD9E2FF, 0x00429B),
                    background: Swatch(0xFEFBFF, 0x1B1B1F), surface: Swatch(0xF3EDF7, 0x211F26), onSurface: Swatch(0x1B1B1F, 0xE3E2E6),
                    onSurfaceVariant: Swatch(0x44464F, 0xC5C6D0), outline: Swatch(0x757780, 0x8F9099))
        case .greenApple:
            Palette(primary: Swatch(0x005927, 0x7ADB8F), onPrimary: Swatch(0xFFFFFF, 0x003917), container: Swatch(0x97F7A9, 0x017737),
                    background: Swatch(0xF6FBF2, 0x0F1510), surface: Swatch(0xEAEFE6, 0x1C211C), onSurface: Swatch(0x181D18, 0xDFE4DB),
                    onSurfaceVariant: Swatch(0x3F493F, 0xBECABC), outline: Swatch(0x6F7A6E, 0x889487))
        case .lavender:
            Palette(primary: Swatch(0x6D41C8, 0xA177FF), onPrimary: Swatch(0xFFFFFF, 0x3D0090), container: Swatch(0xC9B0E6, 0x423271),
                    background: Swatch(0xEDE2FF, 0x111129), surface: Swatch(0xE4D5F8, 0x1D193B), onSurface: Swatch(0x1D1A22, 0xE7E0EC),
                    onSurfaceVariant: Swatch(0x4A4453, 0xCBC3D6), outline: Swatch(0x7B7485, 0x958E9F))
        case .midnightDusk:
            Palette(primary: Swatch(0xBB0054, 0xF02475), onPrimary: Swatch(0xFFFFFF, 0xFFFFFF), container: Swatch(0xEFBAD4, 0x66183C),
                    background: Swatch(0xFFFBFF, 0x16151D), surface: Swatch(0xF9E6F1, 0x281624), onSurface: Swatch(0x1C1B1F, 0xE5E1E5),
                    onSurfaceVariant: Swatch(0x524346, 0xD6C1C4), outline: Swatch(0x847376, 0x9F8C8F))
        case .strawberryDaiquiri:
            Palette(primary: Swatch(0xA10833, 0xFFB2B8), onPrimary: Swatch(0xFFFFFF, 0x67001D), container: Swatch(0xD53855, 0x91002A),
                    background: Swatch(0xFAFAFA, 0x201A1A), surface: Swatch(0xF6EAED, 0x322727), onSurface: Swatch(0x261819, 0xF7DCDD),
                    onSurfaceVariant: Swatch(0x594042, 0xE1BEC0), outline: Swatch(0x8D7071, 0xA9898B))
        case .tako:
            Palette(primary: Swatch(0x66577E, 0xF3B375), onPrimary: Swatch(0xF3B375, 0x38294E), container: Swatch(0xC8BED0, 0x5C4D4B),
                    background: Swatch(0xF7F5FF, 0x21212E), surface: Swatch(0xE8E0EB, 0x2A2A3C), onSurface: Swatch(0x1B1B22, 0xE3E0F2),
                    onSurfaceVariant: Swatch(0x49454E, 0xCBC4CE), outline: Swatch(0x7A757E, 0x958F99))
        }
    }
}

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = AppTheme.standard.palette(pureBlack: false)
}

extension EnvironmentValues {
    /// The current theme's colors, set once by `RootView`.
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}
