import JavaScriptCore

@objc protocol JSElementExports: JSExport {
    func select(_ css: String) -> [JSElement]
    func selectFirst(_ css: String) -> JSElement?
    func text() -> String
    func ownText() -> String
    func data() -> String
    func html() -> String
    func attr(_ name: String) -> String
    func absUrl(_ name: String) -> String
    func tagName() -> String
}

/// Exposes an HTMLNode to scripts. Errors become JavaScript exceptions.
final class JSElement: NSObject, JSElementExports {
    let node: HTMLNode

    init(_ node: HTMLNode) {
        self.node = node
    }

    func select(_ css: String) -> [JSElement] {
        do {
            return try node.select(css).map(JSElement.init)
        } catch {
            JSElement.raise(error)
            return []
        }
    }

    func selectFirst(_ css: String) -> JSElement? {
        do {
            return try node.selectFirst(css).map(JSElement.init)
        } catch {
            JSElement.raise(error)
            return nil
        }
    }

    func text() -> String { node.text() }
    func ownText() -> String { node.ownText() }
    func data() -> String { node.data() }
    func html() -> String { node.html() }
    func attr(_ name: String) -> String { node.attr(name) }
    func absUrl(_ name: String) -> String { node.absUrl(name) }
    func tagName() -> String { node.tagName() }

    static func raise(_ error: Error) {
        guard let context = JSContext.current() else { return }
        context.exception = JSValue(newErrorFromMessage: error.localizedDescription, in: context)
    }
}
