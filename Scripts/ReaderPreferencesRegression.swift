// Standalone Foundation behavior harness, independent of UIKit / SwiftUI.
// Compile with:
// swiftc Ahoge/Domain/Preferences/ReaderParityPreferences.swift Scripts/ReaderPreferencesRegression.swift -o <temporary executable path>
// Then run that executable. A syntax parse is not execution of this harness.
import Foundation

private struct RegressionFailure: Error, CustomStringConvertible {
    let description: String
}
@main
struct ReaderPreferencesRegression {
    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw RegressionFailure(description: message) }
    }
    static func decode(_ json: String) throws -> ReaderParityPreferences {
        try JSONDecoder().decode(ReaderParityPreferences.self, from: Data(json.utf8))
    }
    static func main() throws {
        let empty = try decode("{}")
        try require(empty == .default, "Old preference payloads must keep safe defaults")
        try require(empty.dualPageDisplay == .never && empty.firstPageAlone, "Legacy payload keeps single-page default and isolated cover")
        try require(empty.continuousGap == 12 && empty.webtoonGap == 0, "Legacy long strip and Webtoon must retain distinct default gaps")
        let partial = try decode("{\"cropBorders\":true,\"unknownOptionalMetadata\":{\"value\":1}}")
        var expectedPartial = ReaderParityPreferences.default
        expectedPartial.cropBorders = true
        try require(partial == expectedPartial, "Partial preferences must default missing fields and tolerate unknown optional metadata")
        var value = ReaderParityPreferences.default
        value.dualPageDisplay = .wide
        value.firstPageAlone = false
        value.scale = .original
        value.zoomStart = .right
        value.tapNavigation = .kindle
        value.invertHorizontalTaps = true
        value.invertVerticalTaps = true
        value.animatePages = false
        value.background = .white
        value.cropBorders = true
        value.invertSplitOrder = true
        value.rotateWidePages = true
        value.rotateClockwise = false
        value.continuousGap = 32
        value.webtoonGap = 8
        value.sidePadding = 12
        value.doubleTapZoom = false
        value.allowZoomOut = true
        value.fullscreen = false
        let restored = try JSONDecoder().decode(ReaderParityPreferences.self, from: JSONEncoder().encode(value))
        try require(restored == value, "Every nondefault reader setting must survive a persistence round trip")
        let lower = try decode("{\"continuousGap\":-100,\"webtoonGap\":10000,\"sidePadding\":10000}")
        try require(lower.continuousGap == 0 && lower.webtoonGap == 64 && lower.sidePadding == 25, "Continuous gap and side padding must clamp unsafe imported values")
        let upper = try decode("{\"continuousGap\":10000,\"webtoonGap\":-100,\"sidePadding\":-100}")
        try require(upper.continuousGap == 64 && upper.webtoonGap == 0 && upper.sidePadding == 0, "Continuous gap and side padding must clamp both bounds")
        typealias A = ReaderNavigationAction
        let previous = A.backward, next = A.forward, menu = A.menu
        // Stable Mihon navigation diagrams, top-to-bottom and left-to-right.
        let grids: [(ReaderTapNavigation, [A])] = [
            (.standard, [previous,menu,next, previous,menu,next, previous,menu,next]),
            (.lShape, [previous,previous,previous, previous,menu,next, next,next,next]),
            (.kindle, [menu,menu,menu, previous,next,next, previous,next,next]),
            (.edges, [next,menu,next, next,menu,next, next,previous,next]),
            (.vertical, [previous,previous,previous, menu,menu,menu, next,next,next]),
            (.disabled, Array(repeating: menu, count: 9)),
        ]
        let points = [0.16, 0.5, 0.83]
        for (navigation, grid) in grids {
            for row in 0..<3 {
                for column in 0..<3 {
                    let action = navigation.action(x: points[column], y: points[row], rtl: false,
                        verticalDefault: false, invertHorizontal: false, invertVertical: false)
                    try require(action == grid[row * 3 + column], "\(navigation.rawValue) region \(row),\(column) differs from stable reference")
                    for horizontal in [false, true] {
                        for vertical in [false, true] {
                            let inverted = navigation.action(x: points[column], y: points[row], rtl: false,
                                verticalDefault: false, invertHorizontal: horizontal, invertVertical: vertical)
                            let expectedRow = vertical ? 2 - row : row
                            let expectedColumn = horizontal ? 2 - column : column
                            try require(inverted == grid[expectedRow * 3 + expectedColumn], "\(navigation.rawValue) selected-axis inversion failed")
                        }
                    }
                }
            }
        }
        for row in 0..<3 {
            for column in 0..<3 {
                let rtl = ReaderTapNavigation.standard.action(x: points[column], y: points[row], rtl: true,
                    verticalDefault: false, invertHorizontal: false, invertVertical: false)
                let expected: A = column == 0 ? next : (column == 2 ? previous : menu)
                try require(rtl == expected, "Default horizontal tap direction must follow RTL")
                let vertical = ReaderTapNavigation.standard.action(x: points[column], y: points[row], rtl: true,
                    verticalDefault: true, invertHorizontal: false, invertVertical: false)
                try require(vertical == grids[1].1[row * 3 + column], "Default vertical/continuous navigation must use the stable L layout independent of RTL")
            }
        }
        print("Reader preference regressions passed: legacy defaults, partial decoding, complete round trip, clamps, stable region grids, RTL and selected-axis inversion")
    }
}
