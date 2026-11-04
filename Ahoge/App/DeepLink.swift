import Foundation

/// Where a link into the app leads.
enum DeepLink: Equatable {
    /// A title of a source; `path` is what that source's `details` takes.
    case manga(sourceId: String, path: String)
    case search(String)
    case addRepo(URL)
}

/// Reads `ahoge://` links and web links to a source's website.
///
/// - `ahoge://manga?source=<id>&url=<path>`
/// - `ahoge://search?q=<text>`
/// - `ahoge://add-repo?url=<index.json URL>`
/// - `https://<a source's site>/<path>` (pasted into Browse's "Open link")
enum DeepLinkResolver {
    static func resolve(_ url: URL, sources: [InstalledSource]) -> DeepLink? {
        switch url.scheme?.lowercased() {
        case "ahoge": return resolveApp(url, sources: sources)
        case "http", "https": return resolveWeb(url, sources: sources)
        default: return nil
        }
    }

    private static func resolveApp(_ url: URL, sources: [InstalledSource]) -> DeepLink? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        func value(_ name: String) -> String? {
            components.queryItems?.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        switch components.host?.lowercased() {
        case "add-repo":
            guard let text = value("url"), let repo = URL(string: text), ["http", "https"].contains(repo.scheme?.lowercased()), repo.host != nil else { return nil }
            return .addRepo(repo)
        case "manga":
            guard let id = value("source"), let link = value("url"), isKnown(id, in: sources) else { return nil }
            // A full web address of the source's site is cut down to its path.
            if let absolute = URL(string: link), absolute.scheme != nil,
               case .manga(_, let path)? = resolveWeb(absolute, sources: sources.filter { $0.id == id }) {
                return .manga(sourceId: id, path: path)
            }
            return .manga(sourceId: id, path: link)
        case "search":
            guard let query = value("q")?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else { return nil }
            return .search(query)
        default:
            return nil
        }
    }

    /// The source whose site the link is on, matched by host (ignoring a leading "www.").
    private static func resolveWeb(_ url: URL, sources: [InstalledSource]) -> DeepLink? {
        guard let host = normalizedHost(url.host) else { return nil }
        guard let source = sources.first(where: { normalizedHost(URL(string: $0.baseUrl)?.host) == host }) else { return nil }
        var path = url.path
        if let query = url.query, !query.isEmpty { path += "?" + query }
        guard path.count > 1 else { return nil }
        return .manga(sourceId: source.id, path: path)
    }

    private static func isKnown(_ id: String, in sources: [InstalledSource]) -> Bool {
        id == LocalSource.id || sources.contains { $0.id == id }
    }

    private static func normalizedHost(_ host: String?) -> String? {
        guard var host = host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}
