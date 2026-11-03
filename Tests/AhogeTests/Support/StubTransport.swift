import Foundation
@testable import Ahoge

/// Records requests and answers them from a handler: (status, headers, body, final URL).
final class StubTransport: HTTPTransport {
    typealias Reply = (status: Int, headers: [String: String], body: Data, finalURL: URL?)
    private let handler: (URLRequest) throws -> Reply
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    /// Locked: downloads send pages from several tasks at once.
    var requests: [URLRequest] { lock.withLock { recorded } }

    init(_ handler: @escaping (URLRequest) throws -> Reply) {
        self.handler = handler
    }

    static func text(_ body: String, status: Int = 200, headers: [String: String] = [:]) -> StubTransport {
        StubTransport { _ in (status, headers, Data(body.utf8), nil) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { recorded.append(request) }
        let reply = try handler(request)
        let url = reply.finalURL ?? request.url!
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        return (reply.body, response)
    }
}
