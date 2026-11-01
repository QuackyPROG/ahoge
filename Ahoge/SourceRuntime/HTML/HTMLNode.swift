import Foundation
import SwiftSoup

/// An element (or the document root) with HOST_API.md semantics.
final class HTMLNode {
    let element: Element
    let base: String

    init(element: Element, base: String) {
        self.element = element
        self.base = base
    }

    static func parse(_ body: String, baseUrl: String) throws -> HTMLNode {
        let document = try SwiftSoup.parse(body, baseUrl)
        document.outputSettings().prettyPrint(pretty: false)
        var base = baseUrl
        if let tag = try document.select("base[href]").first(),
           let href = tag.getAttributes()?.get(key: "href"),
           let resolved = WHATWGURL.resolve(href, base: baseUrl) {
            base = resolved
        }
        return HTMLNode(element: document, base: base)
    }

    /// Selectors that already passed SelectorGuard, so repeated selects skip the four regex scans.
    private static var checkedSelectors = Set<String>()
    private static let checkedLock = NSLock()

    private static func assertSupported(_ css: String) throws {
        checkedLock.lock()
        let known = checkedSelectors.contains(css)
        checkedLock.unlock()
        if known { return }
        try SelectorGuard.assertSupported(css)
        checkedLock.lock()
        if checkedSelectors.count >= 4096 { checkedSelectors.removeAll() }
        checkedSelectors.insert(css)
        checkedLock.unlock()
    }

    func select(_ css: String) throws -> [HTMLNode] {
        try Self.assertSupported(css)
        return try element.select(css).array().map { HTMLNode(element: $0, base: base) }
    }

    /// Stops at the first match (document order, the element itself included, as `select` does).
    func selectFirst(_ css: String) throws -> HTMLNode? {
        try Self.assertSupported(css)
        // SwiftSoup has no first-match API; walk the tree like Collector does (document order,
        // root included) and stop at the first element the evaluator accepts.
        let evaluator = try QueryParser.parse(css)
        var stack: [Element] = [element]
        while let current = stack.popLast() {
            if try evaluator.matches(element, current) {
                return HTMLNode(element: current, base: base)
            }
            for child in current.children().array().reversed() { stack.append(child) }
        }
        return nil
    }

    func text() -> String { TextExtraction.text(element) }

    func ownText() -> String { TextExtraction.ownText(element) }

    func data() -> String { TextExtraction.data(element) }

    func html() -> String { (try? element.html()) ?? "" }

    func attr(_ name: String) -> String {
        let value = element.getAttributes()?.get(key: name.lowercased()) ?? ""
        if !value.isEmpty { return value }
        if name.hasPrefix("abs:") { return absUrl(String(name.dropFirst(4))) }
        return ""
    }

    func absUrl(_ name: String) -> String {
        let key = name.lowercased()
        guard let attributes = element.getAttributes(), attributes.hasKey(key: key) else { return "" }
        return WHATWGURL.resolve(attributes.get(key: key), base: base) ?? ""
    }

    func tagName() -> String {
        element is Document ? "#root" : element.tagNameNormal()
    }
}
