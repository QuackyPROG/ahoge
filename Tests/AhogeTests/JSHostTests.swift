import XCTest
@testable import Ahoge

final class JSHostTests: XCTestCase {
    private func host(_ script: String, stub: StubTransport = .text("")) throws -> JSHost {
        try JSHost(script: script, http: HTTPClient(transport: stub))
    }

    private func value<T: Decodable>(_ host: JSHost, _ method: String, _ args: [Any] = [], as: T.Type = T.self) async throws -> T {
        try JSONDecoder().decode(T.self, from: await host.call(method, args))
    }

    func testAsyncMethodParsesHTML() async throws {
        let stub = StubTransport.text("<a href='/m/1'>One</a><a href='/m/2'>Two</a>")
        let h = try host("""
        var source = null;
        source = { popular: async function (page) {
          var res = await http.get("https://s.test/list?page=" + page);
          var doc = html.parse(res.body, res.url);
          return { manga: doc.select("a").map(function (a) { return { url: a.attr("href"), title: a.text(), cover: a.absUrl("href") }; }), hasNextPage: false };
        } };
        """, stub: stub)
        let page = try await value(h, "popular", [2], as: MangaListPage.self)
        XCTAssertEqual(page.manga.map(\.title), ["One", "Two"])
        XCTAssertEqual(page.manga[0].cover, "https://s.test/m/1")
        XCTAssertEqual(stub.requests[0].url?.absoluteString, "https://s.test/list?page=2")
    }

    /// Runs the vectors inside JavaScript from the raw file text, because key order matters
    /// ("key order is preserved") and JSONSerialization does not keep it.
    func testEncodeFormVectorsMatchConformance() throws {
        let h = try host("var source = {};")
        let raw = try String(contentsOf: try XCTUnwrap(Conformance.url()), encoding: .utf8)
        let failures = h.evaluate("""
        (function () {
          var vectors = (\(raw)).http.encodeForm;
          if (!vectors.length) return "no vectors";
          return vectors.filter(function (v) { return __ahoge_encodeForm(v.input) !== v.expected; })
            .map(function (v) { return v.name + ": got " + __ahoge_encodeForm(v.input); }).join("\\n");
        })()
        """)
        XCTAssertEqual(failures, "")
    }

    func testPostObjectBodyIsFormEncodedAndStringBodyHasNoContentType() async throws {
        let stub = StubTransport.text("ok")
        let h = try host("""
        var source = { popular: async function () {
          await http.post("https://s.test/a", { body: { a: "1", b: "x y" } });
          await http.post("https://s.test/b", { body: "raw" });
          return { manga: [], hasNextPage: false };
        } };
        """, stub: stub)
        _ = try await h.call("popular", [1])
        XCTAssertEqual(stub.requests[0].httpBody, Data("a=1&b=x%20y".utf8))
        XCTAssertEqual(stub.requests[0].value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(stub.requests[1].httpBody, Data("raw".utf8))
        XCTAssertNil(stub.requests[1].value(forHTTPHeaderField: "Content-Type"))
    }

    func testCloudflareErrorIsVisibleToScriptAndMapped() async throws {
        let stub = StubTransport.text("<title>Just a moment...</title>", status: 503)
        let h = try host("""
        var source = { popular: async function () {
          try { await http.get("https://s.test/cf"); } catch (e) { if (e instanceof CloudflareError) throw e; }
          return null;
        } };
        """, stub: stub)
        do {
            _ = try await h.call("popular", [1])
            XCTFail("expected Cloudflare")
        } catch SourceError.cloudflare(let url) {
            XCTAssertEqual(url, "https://s.test/cf")
        }
    }

    func testErrorsAndMissingMethods() async throws {
        let h = try host("var source = { latest: async function () { throw new Error('boom'); } };")
        do { _ = try await h.call("latest", [1]); XCTFail() } catch SourceError.script(let message) { XCTAssertEqual(message, "boom") }
        do { _ = try await h.call("details", ["/x"]); XCTFail() } catch SourceError.missingMethod(let name) { XCTAssertEqual(name, "details") }
        XCTAssertThrowsError(try host("var x = 1;"))
        XCTAssertThrowsError(try host("var source = {"))
    }

    func testTimeout() async throws {
        let h = try host("var source = { pages: function () { return new Promise(function () {}); } };")
        do {
            _ = try await h.call("pages", ["/c"], timeout: 0.3)
            XCTFail("expected timeout")
        } catch SourceError.timeout(let message) {
            XCTAssertTrue(message.contains("timed out"))
        }
    }

    func testCancellingTheTaskEndsTheCallBeforeTheTimeout() async throws {
        let h = try host("var source = { pages: function () { return new Promise(function () {}); } };")
        let start = Date()
        let task = Task { try await h.call("pages", ["/c"], timeout: 30) }
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // expected
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testUnserializableResultIsAScriptError() async throws {
        let h = try host("var source = { details: async function () { var o = {}; o.self = o; return o; } };")
        do {
            _ = try await h.call("details", ["/x"])
            XCTFail("expected a script error")
        } catch SourceError.script {
            // expected: JSON.stringify threw on the circular result
        }
    }

    func testSelectFirstReturnsNullWhenNothingMatches() throws {
        let h = try host("var source = {};")
        XCTAssertEqual(h.evaluate("html.parse('<p>x</p>','https://e.com/').selectFirst('span') === null"), "true")
        XCTAssertEqual(h.evaluate("html.parse('<p>x</p>','https://e.com/').selectFirst('p').text()"), "x")
    }

    func testGlobalsMatchJavaScriptCoreContract() throws {
        let h = try host("var source = {};")
        XCTAssertEqual(h.evaluate("typeof URL + ',' + typeof fetch + ',' + typeof setTimeout"), "undefined,undefined,undefined")
        XCTAssertEqual(h.evaluate("atob(btoa('hé'))"), "hé")
        XCTAssertEqual(h.evaluate("(function(){ try { btoa('日'); return 'no'; } catch (e) { return e.name; } })()"), "InvalidCharacterError")
        XCTAssertEqual(h.evaluate("(function(){ try { html.parse('<p>', 'https://e.com/').select(':eq(0)'); return 'no'; } catch (e) { return e.message.indexOf('Unsupported selector: ') === 0 ? 'yes' : e.message; } })()"), "yes")
    }
}
