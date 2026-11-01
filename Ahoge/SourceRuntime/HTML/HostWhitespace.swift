/// HOST_API.md whitespace set: space, tab, LF, CR, FF and NBSP. Never `\s` or Foundation trimming.
enum HostWhitespace {
    static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x20, 0x09, 0x0A, 0x0D, 0x0C, 0xA0: return true
        default: return false
        }
    }

    static func collapse(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        var inRun = false
        for scalar in text.unicodeScalars {
            if isWhitespace(scalar) {
                if !inRun { out.append(" ") }
                inRun = true
            } else {
                out.append(scalar)
                inRun = false
            }
        }
        return String(out)
    }

    static func trim(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var start = 0
        var end = scalars.count
        while start < end, isWhitespace(scalars[start]) { start += 1 }
        while end > start, isWhitespace(scalars[end - 1]) { end -= 1 }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[start..<end])
        return String(view)
    }
}
