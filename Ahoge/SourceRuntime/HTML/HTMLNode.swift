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

    func select(_ css: String) throws -> [HTMLNode] {
        try SelectorGuard.assertSupported(css)
        return try element.select(css).array().map { HTMLNode(element: $0, base: base) }
    }

    func selectFirst(_ css: String) throws -> HTMLNode? {
        try select(css).first
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
