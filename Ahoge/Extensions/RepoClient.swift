import CryptoKit
import Foundation

struct RepoClient {
    let transport: HTTPTransport

    func fetchIndex(_ indexURL: String) async throws -> RepoIndex {
        let data = try await get(indexURL)
        do {
            return try JSONDecoder().decode(RepoIndex.self, from: data)
        } catch {
            throw RepoError.invalidIndex(String(describing: error))
        }
    }

    /// Downloads a source bundle and verifies it against the index sha256.
    func downloadScript(for source: RepoSource, indexURL: String) async throws -> Data {
        guard let url = Self.resolve(source.script, indexURL: indexURL) else { throw RepoError.invalidURL(source.script) }
        let data = try await get(url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == source.sha256.lowercased() else { throw RepoError.checksumMismatch(source.id) }
        return data
    }

    static func resolve(_ path: String, indexURL: String) -> String? {
        WHATWGURL.resolve(path, base: indexURL)
    }

    private func get(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString), url.scheme == "https" || url.scheme == "http" else { throw RepoError.invalidURL(urlString) }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw RepoError.http(response.statusCode, urlString) }
        return data
    }
}
