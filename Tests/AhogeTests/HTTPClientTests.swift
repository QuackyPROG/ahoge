import XCTest
@testable import Ahoge

final class HTTPClientTests: XCTestCase {
    private func spec(_ url: String = "https://s.test/a", method: String = "GET", headers: [String: String] = [:], body: Data? = nil) -> HTTPRequestSpec {
        HTTPRequestSpec(method: method, url: url, headers: headers, body: body)
    }

    func testDefaultUserAgentAndCallerOverride() async throws {
        let stub = StubTransport.text("ok")
        let client = HTTPClient(transport: stub)
        _ = try await client.send(spec())
        _ = try await client.send(spec(headers: ["user-agent": "Ahoge/2.0"]))
        XCTAssertEqual(stub.requests[0].value(forHTTPHeaderField: "User-Agent"), HTTPClient.defaultUserAgent)
        XCTAssertEqual(stub.requests[1].value(forHTTPHeaderField: "User-Agent"), "Ahoge/2.0")
    }

    func testCookiesAreStoredAndSent() async throws {
        let stub = StubTransport { request in
            request.url?.path == "/login" ? (200, ["Set-Cookie": "sid=42"], Data(), nil) : (200, [:], Data(), nil)
        }
        let client = HTTPClient(transport: stub)
        _ = try await client.send(spec("https://s.test/login"))
        let response = try await client.send(spec("https://s.test/page"))
        XCTAssertEqual(stub.requests[1].value(forHTTPHeaderField: "Cookie"), "sid=42")
        XCTAssertNil(response.headers["set-cookie"])
    }

    func testResponseNormalization() async throws {
        var body = Data([0xEF, 0xBB, 0xBF])
        body.append(Data("héllo".utf8))
        body.append(0xFF)
        let stub = StubTransport { _ in (201, ["X-Thing": "v", "Set-Cookie": "a=1"], body, URL(string: "https://s.test/final")) }
        let response = try await HTTPClient(transport: stub).send(spec())
        XCTAssertEqual(response.status, 201)
        XCTAssertEqual(response.url, "https://s.test/final")
        XCTAssertEqual(response.headers["x-thing"], "v")
        XCTAssertEqual(response.headers["set-cookie"], "a=1")
        XCTAssertEqual(response.body, "héllo\u{FFFD}")
    }

    func testBodyIsSentAsBytesWithoutContentType() async throws {
        let stub = StubTransport.text("ok")
        _ = try await HTTPClient(transport: stub).send(spec(method: "POST", body: Data("raw".utf8)))
        XCTAssertEqual(stub.requests[0].httpBody, Data("raw".utf8))
        XCTAssertNil(stub.requests[0].value(forHTTPHeaderField: "Content-Type"))
    }

    func testCloudflareChallengeThrows() async {
        let stub = StubTransport.text("<html><title>Just a moment...</title></html>", status: 403)
        do {
            _ = try await HTTPClient(transport: stub).send(spec("https://s.test/x"))
            XCTFail("expected a Cloudflare error")
        } catch HTTPClientError.cloudflare(let url) {
            XCTAssertEqual(url, "https://s.test/x")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testCloudflareVectorsFromConformance() throws {
        let http = try XCTUnwrap(Conformance.load()["http"] as? [String: Any])
        let vectors = try XCTUnwrap(http["isCloudflareChallenge"] as? [[String: Any]])
        XCTAssertFalse(vectors.isEmpty)
        for v in vectors {
            let headers = (v["headers"] as? [String: String] ?? [:]).reduce(into: [String: String]()) { $0[$1.key.lowercased()] = $1.value }
            let actual = HTTPClient.isCloudflareChallenge(status: v["status"] as? Int ?? 0, headers: headers, body: v["body"] as? String ?? "")
            XCTAssertEqual(actual, v["expected"] as? Bool, v["name"] as? String ?? "")
        }
    }
}
