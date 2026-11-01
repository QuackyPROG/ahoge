import XCTest
@testable import Ahoge

final class WHATWGURLTests: XCTestCase {
    private func check(_ input: String, _ base: String, _ expected: String?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(WHATWGURL.resolve(input, base: base), expected, "input: \(input)", file: file, line: line)
    }

    func testRelativeAndRoot() {
        check("../two/", "https://example.com/manga/one/", "https://example.com/manga/two/")
        check("/c.jpg", "https://example.com/manga/one/", "https://example.com/c.jpg")
        check("./a/./b/../c", "https://e.com/x/y", "https://e.com/x/a/c")
        check("/a/b/..", "https://e.com/", "https://e.com/a/")
    }

    func testSchemeRelativeAndBackslashes() {
        check("//cdn.example.net/c.jpg", "https://example.com/", "https://cdn.example.net/c.jpg")
        check("\\img\\a.png", "https://e.com/x/", "https://e.com/img/a.png")
    }

    func testQueryFragmentAndEmpty() {
        check("?page=2", "https://e.com/a/b?x=1#f", "https://e.com/a/b?page=2")
        check("#top", "https://e.com/a/b?x=1#f", "https://e.com/a/b?x=1#top")
        check("", "https://e.com/a/b?x=1#f", "https://e.com/a/b?x=1")
        check("?q=a b'c", "https://e.com/p", "https://e.com/p?q=a%20b%27c")
    }

    func testEncodingAndCleanup() {
        check("a b.jpg", "https://e.com/x/", "https://e.com/x/a%20b.jpg")
        check("é.jpg", "https://e.com/", "https://e.com/%C3%A9.jpg")
        check("  /a\n/b\t ", "https://e.com/", "https://e.com/a/b")
        check("/already%20encoded", "https://e.com/", "https://e.com/already%20encoded")
    }

    func testAbsoluteURLs() {
        check("HTTPS://CDN.Example.COM:443/A", "https://e.com/", "https://cdn.example.com/A")
        check("http://e.com:80/", "https://e.com/", "http://e.com/")
        check("http://e.com:8080/p", "https://e.com/", "http://e.com:8080/p")
        check("https://e.com", "https://x.com/", "https://e.com/")
        check("https:foo", "https://e.com/x/", "https://e.com/x/foo")
        check("javascript:void(0)", "https://e.com/", "javascript:void(0)")
    }

    func testFailures() {
        check("https://", "https://e.com/", nil)
        check("a", "not a url", nil)
        check("http://e.com:99999/", "https://e.com/", nil)
    }
}
