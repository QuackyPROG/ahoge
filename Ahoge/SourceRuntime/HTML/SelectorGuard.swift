import Foundation

/// HOST_API.md "Forbidden selectors": the same four regular expressions as runtime/html.mjs.
enum SelectorGuard {
    struct UnsupportedSelector: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static let specs: [(pattern: String, reason: String)] = [
        (#":(eq|lt|gt)\("#, "jQuery positional pseudo-class; use :nth-child() or index the result array"),
        (#":(first|last|even|odd)(?![-A-Za-z0-9_])"#, "jQuery positional pseudo-class; use :first-child, :last-child or :nth-child()"),
        (#":(matches|matchesOwn|matchesText|matchesWholeText|matchesWholeOwnText|containsData|containsWholeText|containsWholeOwnText)\("#, "Jsoup-only pseudo-class; filter in JavaScript"),
        (#":contains(Own)?\(\s*["']"#, "write the :contains argument unquoted"),
    ]

    private static let rules: [(NSRegularExpression, String)] = specs.map { spec in
        // The patterns are constants; a failure here is a programming error caught by the tests.
        (try! NSRegularExpression(pattern: spec.pattern, options: [.caseInsensitive]), spec.reason)
    }

    static func assertSupported(_ css: String) throws {
        let range = NSRange(css.startIndex..., in: css)
        for (regex, reason) in rules {
            if let match = regex.firstMatch(in: css, range: range), let matched = Range(match.range, in: css) {
                throw UnsupportedSelector(message: "Unsupported selector: \(css[matched]) (\(reason))")
            }
        }
    }
}
