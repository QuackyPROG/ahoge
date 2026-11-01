import Foundation

struct HTTPRequestSpec {
    var method: String
    var url: String
    var headers: [String: String]
    /// Request body bytes. The JS bootstrap has already form-encoded objects and set Content-Type.
    var body: Data?
}

struct HTTPResponseData: Equatable {
    let status: Int
    let url: String
    let headers: [String: String]
    let body: String
}

enum HTTPClientError: LocalizedError, Equatable {
    case invalidURL(String)
    case cloudflare(url: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "Invalid URL: \(url)"
        case .cloudflare(let url): return "Cloudflare challenge at \(url)"
        }
    }
}

/// The `http` host object of HOST_API.md, minus the JS-side form encoding.
final class HTTPClient {
    static let defaultUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    let jar: CookieJar
    private let transport: HTTPTransport

    init(transport: HTTPTransport = URLSessionTransport.forSources, jar: CookieJar = CookieJar()) {
        self.transport = transport
        self.jar = jar
    }

    func send(_ spec: HTTPRequestSpec) async throws -> HTTPResponseData {
        guard let url = URL(string: spec.url), url.host != nil else { throw HTTPClientError.invalidURL(spec.url) }
        var request = URLRequest(url: url)
        request.httpMethod = spec.method
        for (name, value) in spec.headers { request.setValue(value, forHTTPHeaderField: name) }
        let names = Set(spec.headers.keys.map { $0.lowercased() })
        if !names.contains("user-agent") { request.setValue(Self.defaultUserAgent, forHTTPHeaderField: "User-Agent") }
        if !names.contains("cookie"), let host = url.host, let cookie = jar.header(for: host) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        request.httpBody = spec.body

        let (data, response) = try await transport.send(request)
        let finalURL = response.url ?? url
        let rawHeaders = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let name = pair.key as? String, let value = pair.value as? String { result[name] = value }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: rawHeaders, for: finalURL)
        if let host = finalURL.host { jar.store(cookies, responseHost: host) }

        var headers = [String: String]()
        for (name, value) in rawHeaders { headers[name.lowercased()] = value }
        // Foundation joins repeated Set-Cookie headers with ", "; rebuild one "name=value" per line.
        headers["set-cookie"] = cookies.isEmpty ? nil : cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "\n")

        let body = Self.decodeUTF8(data)
        if Self.isCloudflareChallenge(status: response.statusCode, headers: headers, body: body) {
            throw HTTPClientError.cloudflare(url: spec.url)
        }
        return HTTPResponseData(status: response.statusCode, url: finalURL.absoluteString, headers: headers, body: body)
    }

    static func decodeUTF8(_ data: Data) -> String {
        let bytes = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data
        return String(decoding: bytes, as: UTF8.self)
    }

    static func isCloudflareChallenge(status: Int, headers: [String: String], body: String) -> Bool {
        guard status == 403 || status == 503 else { return false }
        if headers["cf-mitigated"] == "challenge" { return true }
        return body.contains("<title>Just a moment...</title>")
    }
}
