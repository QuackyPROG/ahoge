import Foundation

/// Cookies obtained in the web view (e.g. Cloudflare clearance) persist in HTTPCookieStorage.shared.
enum SharedCookies {
    static func cookies(forBaseURL baseURL: String) -> [HTTPCookie] {
        guard let host = URL(string: baseURL)?.host?.lowercased() else { return [] }
        return (HTTPCookieStorage.shared.cookies ?? []).filter { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return host == domain.lowercased() || host.hasSuffix("." + domain.lowercased())
        }
    }

    static func store(_ cookies: [HTTPCookie]) {
        for cookie in cookies { HTTPCookieStorage.shared.setCookie(cookie) }
    }

    static func removeAll() {
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
    }
}
