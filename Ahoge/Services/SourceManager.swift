import Foundation

/// Creates one ScriptSource per installed source and reuses it until the script changes.
@MainActor
final class SourceManager: ObservableObject {
    private let extensions: ExtensionStore
    private var cache: [String: (sha256: String, source: ScriptSource)] = [:]

    init(extensions: ExtensionStore) {
        self.extensions = extensions
    }

    func installed(_ id: String) -> InstalledSource? {
        extensions.installed.first { $0.id == id }
    }

    func source(_ id: String) throws -> ScriptSource {
        guard let info = installed(id) else { throw SourceError.notInstalled(id) }
        if let hit = cache[id], hit.sha256 == info.sha256 { return hit.source }
        let jar = CookieJar()
        jar.seed(SharedCookies.cookies(forBaseURL: info.baseUrl))
        let source = try ScriptSource(script: try extensions.scriptText(for: id), http: HTTPClient(jar: jar))
        cache[id] = (info.sha256, source)
        return source
    }

    /// Called after the web view: persists the cookies and hands them to running sources.
    func importWebCookies(_ cookies: [HTTPCookie]) {
        SharedCookies.store(cookies)
        for entry in cache.values { entry.source.host.http.jar.seed(cookies) }
    }

    func resetSessions() {
        cache.removeAll()
    }
}
