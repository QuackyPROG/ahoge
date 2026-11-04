import CoreGraphics

/// Groups a chapter's pages into two-page spreads for the dual page view.
enum PagePairing {
    /// Page indices grouped one or two at a time, in reading order; each group is in screen order,
    /// left to right (so right to left reading puts the later page first). Wide pages, and a page
    /// whose partner would be wide, stand alone. `sizes` holds the pages measured so far; the rest
    /// count as single pages. `firstAlone` shifts the pairs by one (Mihon's "shift").
    static func pairs(pages: Int, sizes: [Int: CGSize], rtl: Bool, firstAlone: Bool) -> [[Int]] {
        func isWide(_ index: Int) -> Bool { sizes[index].map(PageGeometry.isWide) ?? false }
        var groups: [[Int]] = []
        var index = 0
        if firstAlone, pages > 0 {
            groups.append([0])
            index = 1
        }
        while index < pages {
            if isWide(index) || index + 1 >= pages || isWide(index + 1) {
                groups.append([index])
                index += 1
            } else {
                groups.append(rtl ? [index + 1, index] : [index, index + 1])
                index += 2
            }
        }
        return groups
    }
}
