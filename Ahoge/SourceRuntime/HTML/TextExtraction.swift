import SwiftSoup

/// text(), ownText() and data() exactly as HOST_API.md specifies (not SwiftSoup's own versions).
enum TextExtraction {
    static let blockTags: Set<String> = [
        "address", "article", "aside", "blockquote", "br", "dd", "div", "dl", "dt", "fieldset",
        "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header",
        "hr", "li", "main", "nav", "ol", "p", "pre", "section", "table", "tbody", "td", "tfoot",
        "th", "thead", "tr", "ul",
    ]

    private struct Builder {
        var out = ""
        var endsWithSpace: Bool { out.last == " " }

        mutating func appendText(_ raw: String) {
            var collapsed = HostWhitespace.collapse(raw)
            if collapsed.hasPrefix(" ") && endsWithSpace { collapsed.removeFirst() }
            out += collapsed
        }
    }

    static func text(_ node: Node) -> String {
        var builder = Builder()
        walk(node, &builder)
        return HostWhitespace.trim(builder.out)
    }

    private static func walk(_ node: Node, _ builder: inout Builder) {
        if let textNode = node as? TextNode {
            builder.appendText(textNode.getWholeText())
            return
        }
        guard let element = node as? Element else { return }
        let name = element.tagNameNormal()
        if name == "script" || name == "style" { return }
        let isBlock = blockTags.contains(name)
        if isBlock, !builder.out.isEmpty, !builder.endsWithSpace { builder.out += " " }
        for child in element.getChildNodes() { walk(child, &builder) }
        if isBlock, element.nextSibling() is TextNode, !builder.endsWithSpace { builder.out += " " }
    }

    static func ownText(_ element: Element) -> String {
        var builder = Builder()
        for child in element.getChildNodes() {
            if let textNode = child as? TextNode {
                builder.appendText(textNode.getWholeText())
            } else if let br = child as? Element, br.tagNameNormal() == "br", !builder.endsWithSpace {
                builder.out += " "
            }
        }
        return HostWhitespace.trim(builder.out)
    }

    static func data(_ node: Node) -> String {
        var out = ""
        func walk(_ node: Node) {
            if let comment = node as? Comment {
                out += comment.getData()
                return
            }
            guard let element = node as? Element else { return }
            let name = element.tagNameNormal()
            if name == "script" || name == "style" {
                for child in element.getChildNodes() {
                    if let dataNode = child as? DataNode {
                        out += dataNode.getWholeData()
                    } else if let textNode = child as? TextNode {
                        out += textNode.getWholeText()
                    }
                }
                return
            }
            for child in element.getChildNodes() { walk(child) }
        }
        walk(node)
        return out
    }
}
