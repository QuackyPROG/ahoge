import Foundation

/// A typed view of one source script.
final class ScriptSource: MangaSource {
    let host: JSHost

    var hasPreferences: Bool { host.hasMethod("preferences") }

    init(script: String, http: HTTPClient = HTTPClient()) throws {
        host = try JSHost(script: script, http: http)
    }

    func popular(page: Int) async throws -> MangaListPage { try await call("popular", [page]) }
    func latest(page: Int) async throws -> MangaListPage { try await call("latest", [page]) }
    func search(query: String, page: Int) async throws -> MangaListPage { try await call("search", [query, page]) }
    func search(query: String, page: Int, filters: FilterState) async throws -> MangaListPage {
        guard !filters.isEmpty else { return try await search(query: query, page: page) }
        return try await call("search", [query, page, JSONArgument(json: filters.json())])
    }

    /// The source's filter list, or none when the script has no `filters` method.
    func filters() async throws -> [SourceFilter] {
        guard host.hasMethod("filters") else { return [] }
        let list: FilterList = try await call("filters", [])
        return list.filters
    }
    /// The source's settings schema, or none when the script has no `preferences` method
    /// (proposed host API v2; every current extension has none).
    func preferences() async throws -> [SourcePreference] {
        guard host.hasMethod("preferences") else { return [] }
        return try await call("preferences", [])
    }

    /// Hands saved settings to the script as `this.prefs`. Does nothing for a script without
    /// `preferences`, so sources written for host API v1 see no change.
    func applyPreferences(json: String) {
        guard host.hasMethod("preferences") else { return }
        host.setSourceProperty("prefs", json: json)
    }

    func details(url: String) async throws -> MangaDetails { try await call("details", [url]) }
    func chapters(url: String) async throws -> [SourceChapter] { try await call("chapters", [url]) }
    func pages(url: String) async throws -> [SourcePage] { try await call("pages", [url]) }

    private func call<T: Decodable>(_ method: String, _ arguments: [Any]) async throws -> T {
        let data = try await host.call(method, arguments)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SourceError.decoding("\(method) returned unexpected data: \(error)")
        }
    }
}
