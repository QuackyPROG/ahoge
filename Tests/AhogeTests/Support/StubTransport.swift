import Foundation
@testable import Ahoge

/// Records requests and answers them from a handler: (status, headers, body, final URL).
final class StubTransport: HTTPTransport {
    typealias Reply = (status: Int, headers: [String: String], body: Data, finalURL: URL?)
    private let handler: (URLRequest) throws -> Reply
    private(set) var requests: [URLRequest] = []

    init(_ handler: @escaping (URLRequest) throws -> Reply) {
        self.handler = handler
    }

    static func text(_ body: String, status: Int = 200, headers: [String: String] = [:]) -> StubTransport {
        StubTransport { _ in (status, headers, Data(body.utf8), nil) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let reply = try handler(request)
        let url = reply.finalURL ?? request.url!
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        return (reply.body, response)
    }
}
