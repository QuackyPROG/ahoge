import XCTest
@testable import Ahoge

final class HTMLConformanceTests: XCTestCase {
    func testEveryConformanceCase() throws {
        let file = try Conformance.load()
        let defaultBase = try XCTUnwrap(file["baseUrl"] as? String)
        let cases = try XCTUnwrap(file["cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 50)
        var failures: [String] = []
        for c in cases {
            let name = c["name"] as? String ?? "?"
            do {
                let doc = try HTMLNode.parse(c["html"] as? String ?? "", baseUrl: c["baseUrl"] as? String ?? defaultBase)
                let actual = try run(doc, c)
                if !Conformance.matches(actual, c["expected"]) {
                    failures.append("\(name): expected \(String(describing: c["expected"] ?? "nil")) got \(actual)")
                }
            } catch {
                failures.append("\(name): threw \(error.localizedDescription)")
            }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures.count) conformance failures:\n" + failures.joined(separator: "\n"))
    }

    func testDocumentRootTagName() throws {
        XCTAssertEqual(try HTMLNode.parse("<p>x</p>", baseUrl: "https://e.com/").tagName(), "#root")
    }

    private func run(_ doc: HTMLNode, _ c: [String: Any]) throws -> Any {
        let op = c["op"] as? String ?? ""
        let selector = c["select"] as? String ?? ""
        switch op {
        case "count":
            return try doc.select(selector).count
        case "firstIsNull":
            return try doc.selectFirst(selector) == nil
        case "throws":
            do {
                _ = try doc.select(selector)
                return false
            } catch {
                return error.localizedDescription.hasPrefix("Unsupported selector: ")
            }
        default:
            break
        }
        let target: HTMLNode?
        if c["root"] as? Bool == true {
            target = doc
        } else {
            target = try doc.selectFirst(selector)
        }
        guard let target else { return "selector matched nothing: \(selector)" }
        let arg = c["arg"] as? String ?? ""
        switch op {
        case "selfSelectCount": return try target.select(arg).count
        case "attr": return target.attr(arg)
        case "absUrl": return target.absUrl(arg)
        case "text": return target.text()
        case "ownText": return target.ownText()
        case "data": return target.data()
        case "html": return target.html()
        case "tagName": return target.tagName()
        default: return "unknown op \(op)"
        }
    }
}
