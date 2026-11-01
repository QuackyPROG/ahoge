import XCTest
@testable import Ahoge

final class CookieJarTests: XCTestCase {
    private func cookies(_ header: String, url: String) -> [HTTPCookie] {
        HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": header], for: URL(string: url)!)
    }

    func testHostOnlyCookieMatchesExactHost() {
        let jar = CookieJar()
        jar.store(cookies("a=1", url: "https://site.test/"), responseHost: "site.test")
        XCTAssertEqual(jar.header(for: "site.test"), "a=1")
        XCTAssertNil(jar.header(for: "cdn.site.test"))
    }

    func testDomainCookieMatchesSubdomains() {
        let jar = CookieJar()
        jar.store(cookies("b=2; Domain=site.test", url: "https://www.site.test/"), responseHost: "www.site.test")
        XCTAssertEqual(jar.header(for: "site.test"), "b=2")
        XCTAssertEqual(jar.header(for: "img.site.test"), "b=2")
        XCTAssertNil(jar.header(for: "other.test"))
    }

    func testReplacementKeepsOrderAndExpiryDeletes() {
        let jar = CookieJar()
        jar.store(cookies("a=1", url: "https://s.test/"), responseHost: "s.test")
        jar.store(cookies("b=2", url: "https://s.test/"), responseHost: "s.test")
        jar.store(cookies("a=3", url: "https://s.test/"), responseHost: "s.test")
        XCTAssertEqual(jar.header(for: "s.test"), "a=3; b=2")
        jar.store(cookies("a=; Expires=Thu, 01 Jan 1970 00:00:00 GMT", url: "https://s.test/"), responseHost: "s.test")
        XCTAssertEqual(jar.header(for: "s.test"), "b=2")
    }

    func testSeedFromWebViewCookies() {
        let jar = CookieJar()
        let cookie = HTTPCookie(properties: [.name: "cf_clearance", .value: "x", .domain: ".site.test", .path: "/"])!
        jar.seed([cookie])
        XCTAssertEqual(jar.header(for: "www.site.test"), "cf_clearance=x")
    }
}
