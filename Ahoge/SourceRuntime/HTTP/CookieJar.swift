import Foundation

/// In-memory cookie jar with HOST_API.md semantics (host-only vs Domain cookies, insertion order).
final class CookieJar {
    struct Cookie: Equatable {
        let name: String
        var value: String
        let domain: String
        let hostOnly: Bool
    }

    private var cookies: [Cookie] = []
    private let lock = NSLock()

    /// Stores cookies parsed from a response whose final URL host is `responseHost`.
    func store(_ received: [HTTPCookie], responseHost: String, now: Date = Date()) {
        let host = responseHost.lowercased()
        lock.lock()
        defer { lock.unlock() }
        for cookie in received where !cookie.name.isEmpty {
            let hostOnly = !cookie.domain.hasPrefix(".")
            let domain = hostOnly ? host : String(cookie.domain.dropFirst()).lowercased()
            if !hostOnly && !(host == domain || host.hasSuffix("." + domain)) { continue }
            upsert(cookie, domain: domain, hostOnly: hostOnly, now: now)
        }
    }

    /// Adds cookies obtained elsewhere (the WebView used for Cloudflare checks).
    func seed(_ received: [HTTPCookie], now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        for cookie in received where !cookie.name.isEmpty {
            let hostOnly = !cookie.domain.hasPrefix(".")
            let domain = (hostOnly ? cookie.domain : String(cookie.domain.dropFirst())).lowercased()
            upsert(cookie, domain: domain, hostOnly: hostOnly, now: now)
        }
    }

    func header(for host: String) -> String? {
        let h = host.lowercased()
        lock.lock()
        defer { lock.unlock() }
        let matching = cookies.filter { $0.hostOnly ? $0.domain == h : (h == $0.domain || h.hasSuffix("." + $0.domain)) }
        return matching.isEmpty ? nil : matching.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    func removeAll() {
        lock.lock()
        cookies.removeAll()
        lock.unlock()
    }

    private func upsert(_ cookie: HTTPCookie, domain: String, hostOnly: Bool, now: Date) {
        let index = cookies.firstIndex { $0.name == cookie.name && $0.domain == domain && $0.hostOnly == hostOnly }
        if let expires = cookie.expiresDate, expires <= now {
            if let index { cookies.remove(at: index) }
            return
        }
        if let index {
            cookies[index].value = cookie.value
        } else {
            cookies.append(Cookie(name: cookie.name, value: cookie.value, domain: domain, hostOnly: hostOnly))
        }
    }
}
