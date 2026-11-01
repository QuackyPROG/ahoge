import JavaScriptCore
import SwiftSoup

@objc protocol JSElementExports: JSExport {
    func select(_ css: String) -> [JSElement]
    func selectFirst(_ css: String) -> JSValue
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

    /// Returns the element, or JavaScript `null` (an Objective-C nil would arrive as `undefined`).
    func selectFirst(_ css: String) -> JSValue {
        let context = JSContext.current()!
        do {
            if let found = try node.selectFirst(css) {
                return JSValue(object: JSElement(found), in: context)
            }
        } catch {
            JSElement.raise(error)
        }
        return JSValue(nullIn: context)
    }

    func text() -> String { node.text() }
    func ownText() -> String { node.ownText() }
    func data() -> String { node.data() }
    func html() -> String { node.html() }
    func attr(_ name: String) -> String { node.attr(name) }
    func absUrl(_ name: String) -> String { node.absUrl(name) }
    func tagName() -> String { node.tagName() }

    /// SwiftSoup's own errors carry their text in an enum payload, not in `localizedDescription`.
    private static func message(of error: Error) -> String {
        if let soup = error as? SwiftSoup.Exception, case .Error(_, let message) = soup {
            return message
        }
        return error.localizedDescription
    }

    static func raise(_ error: Error) {
        guard let context = JSContext.current() else { return }
        context.exception = JSValue(newErrorFromMessage: message(of: error), in: context)
    }
}
