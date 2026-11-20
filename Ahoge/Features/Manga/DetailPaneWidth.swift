import CoreGraphics

/// Width of the manga page's details pane beside the chapter list in regular width.
enum DetailPaneWidth {
    static let share: CGFloat = 0.4
    static let minimum: CGFloat = 240
    static let maximum: CGFloat = 400

    /// About 40 % of `available`, at least 240 pt and at most 400 pt, and never more than half,
    /// so the chapter list always gets the larger part.
    static func width(available: CGFloat) -> CGFloat {
        min(maximum, available / 2, max(minimum, available * share))
    }
}
