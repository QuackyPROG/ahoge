import XCTest
@testable import Ahoge

final class AppThemeTests: XCTestCase {
    func testPureBlackOnlyChangesDarkBackgrounds() {
        for theme in AppTheme.allCases {
            let normal = theme.palette(pureBlack: false)
            let black = theme.palette(pureBlack: true)
            XCTAssertEqual(black.background.dark, 0x000000, theme.title)
            XCTAssertEqual(black.background.light, normal.background.light, theme.title)
            XCTAssertEqual(black.surface.light, normal.surface.light, theme.title)
            XCTAssertEqual(black.primary, normal.primary, theme.title)
        }
    }

    func testThemesHaveDistinctAccents() {
        let accents = Set(AppTheme.allCases.map { $0.palette(pureBlack: false).primary.dark })
        XCTAssertEqual(accents.count, AppTheme.allCases.count)
    }

    func testMihonDefaultColors() {
        let palette = AppTheme.standard.palette(pureBlack: false)
        XCTAssertEqual(palette.primary, Swatch(0x0058CA, 0xB0C6FF))
        XCTAssertEqual(palette.background.dark, 0x1B1B1F)
    }

    func testModes() {
        XCTAssertNil(ThemeMode.system.colorScheme)
        XCTAssertEqual(ThemeMode.dark.colorScheme, .dark)
    }
}
