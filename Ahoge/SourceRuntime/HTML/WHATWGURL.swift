import Foundation

/// WHATWG URL Standard resolution for http(s) URLs, as HOST_API.md `absUrl()` requires.
/// Foundation's `URL(string:relativeTo:)` follows RFC 3986 and differs (spaces, backslashes, ports).
enum WHATWGURL {
    struct Components {
        var scheme: String
        var authority: String
        var path: String
        var query: String?
        var fragment: String?

        var serialized: String {
            var s = scheme + "://" + authority + path
            if let query { s += "?" + query }
            if let fragment { s += "#" + fragment }
            return s
        }
    }

    private static let defaultPorts = ["http": "80", "https": "443", "ws": "80", "wss": "443", "ftp": "21"]

    /// Resolves `input` against `base`; nil when either cannot be parsed.
    static func resolve(_ input: String, base: String) -> String? {
        guard let baseURL = parseAbsolute(base) else { return nil }
        let s = clean(input)
        if let scheme = leadingScheme(s), defaultPorts[scheme.lowercased()] == nil {
            // Non-special absolute URLs (javascript:, data:, mailto:) are kept as written.
            return scheme.lowercased() + s.dropFirst(scheme.count)
        }
        return resolve(cleaned: s, base: baseURL)?.serialized
    }

    private static func parseAbsolute(_ string: String) -> Components? {
        let s = clean(string)
        guard let scheme = leadingScheme(s), defaultPorts[scheme.lowercased()] != nil else { return nil }
        let rest = s.dropFirst(scheme.count + 1)
        return authorityAndPath(scheme: scheme.lowercased(), String(rest.drop { $0 == "/" || $0 == "\\" }))
    }

    private static func resolve(cleaned s: String, base: Components) -> Components? {
        if let scheme = leadingScheme(s) {
            let lower = scheme.lowercased()
            let rest = String(s.dropFirst(scheme.count + 1))
            if lower == base.scheme && !rest.hasPrefix("/") && !rest.hasPrefix("\\") {
                return relative(rest, base: base)
            }
            return authorityAndPath(scheme: lower, String(rest.drop { $0 == "/" || $0 == "\\" }))
        }
        if s.hasPrefix("//") || s.hasPrefix("\\\\") || s.hasPrefix("/\\") || s.hasPrefix("\\/") {
            return authorityAndPath(scheme: base.scheme, String(s.drop { $0 == "/" || $0 == "\\" }))
        }
        return relative(s, base: base)
    }

    private static func relative(_ s: String, base: Components) -> Components? {
        var result = base
        if s.isEmpty {
            result.fragment = nil
            return result
        }
        let parts = splitPathQueryFragment(s)
        if parts.path.isEmpty {
            if let query = parts.query { result.query = encodeQuery(query) }
            result.fragment = parts.fragment.map(encodeFragment)
            return result
        }
        let path = parts.path.hasPrefix("/") ? parts.path : directory(of: base.path) + parts.path
        result.path = normalizePath(path)
        result.query = parts.query.map(encodeQuery)
        result.fragment = parts.fragment.map(encodeFragment)
        return result
    }

    private static func authorityAndPath(scheme: String, _ s: String) -> Components? {
        let end = s.firstIndex { $0 == "/" || $0 == "\\" || $0 == "?" || $0 == "#" } ?? s.endIndex
        guard let authority = normalizeAuthority(String(s[..<end]), scheme: scheme) else { return nil }
        let parts = splitPathQueryFragment(String(s[end...]))
        let path = parts.path.isEmpty ? "/" : parts.path
        return Components(
            scheme: scheme,
            authority: authority,
            path: normalizePath(path),
            query: parts.query.map(encodeQuery),
            fragment: parts.fragment.map(encodeFragment)
        )
    }

    private static func normalizeAuthority(_ raw: String, scheme: String) -> String? {
        var userinfo = ""
        var hostPort = raw
        if let at = raw.lastIndex(of: "@") {
            userinfo = String(raw[...at])
            hostPort = String(raw[raw.index(after: at)...])
        }
        var host = hostPort
        var port = ""
        if hostPort.hasPrefix("[") {
            guard let close = hostPort.firstIndex(of: "]") else { return nil }
            host = String(hostPort[...close])
            let after = hostPort[hostPort.index(after: close)...]
            if after.hasPrefix(":") {
                port = String(after.dropFirst())
            } else if !after.isEmpty {
                return nil
            }
        } else if let colon = hostPort.lastIndex(of: ":") {
            host = String(hostPort[..<colon])
            port = String(hostPort[hostPort.index(after: colon)...])
        }
        host = host.lowercased()
        guard !host.isEmpty else { return nil }
        if !port.isEmpty {
            guard port.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(port), number <= 65535 else { return nil }
            port = String(number) == defaultPorts[scheme] ? "" : String(number)
        }
        return userinfo + host + (port.isEmpty ? "" : ":" + port)
    }

    private static func splitPathQueryFragment(_ s: String) -> (path: String, query: String?, fragment: String?) {
        var rest = Substring(s)
        var fragment: String?
        if let hash = rest.firstIndex(of: "#") {
            fragment = String(rest[rest.index(after: hash)...])
            rest = rest[..<hash]
        }
        var query: String?
        if let mark = rest.firstIndex(of: "?") {
            query = String(rest[rest.index(after: mark)...])
            rest = rest[..<mark]
        }
        return (String(rest).replacingOccurrences(of: "\\", with: "/"), query, fragment)
    }

    private static func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "/" }
        return String(path[...slash])
    }

    private static func normalizePath(_ path: String) -> String {
        let segments = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)
        var output: [String] = []
        for (index, raw) in segments.enumerated() {
            let isLast = index == segments.count - 1
            let lower = raw.lowercased()
            if lower == "." || lower == "%2e" {
                if isLast { output.append("") }
            } else if ["..", ".%2e", "%2e.", "%2e%2e"].contains(lower) {
                if !output.isEmpty { output.removeLast() }
                if isLast { output.append("") }
            } else {
                output.append(encodePath(raw))
            }
        }
        return "/" + output.joined(separator: "/")
    }

    private static func leadingScheme(_ s: String) -> String? {
        guard let colon = s.firstIndex(of: ":") else { return nil }
        let candidate = s[..<colon]
        guard let first = candidate.unicodeScalars.first, first.isASCII, first.properties.isAlphabetic else { return nil }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+-.".unicodeScalars)
        guard candidate.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return String(candidate)
    }

    private static func clean(_ input: String) -> String {
        var scalars = Array(input.unicodeScalars.filter { $0 != "\t" && $0 != "\n" && $0 != "\r" })
        while let first = scalars.first, first.value <= 0x20 { scalars.removeFirst() }
        while let last = scalars.last, last.value <= 0x20 { scalars.removeLast() }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    private static func encodePath(_ s: String) -> String {
        percentEncode(s) { $0 < 0x21 || $0 > 0x7E || [0x22, 0x23, 0x3C, 0x3E, 0x3F, 0x60, 0x7B, 0x7D].contains($0) }
    }

    private static func encodeQuery(_ s: String) -> String {
        percentEncode(s) { $0 < 0x21 || $0 > 0x7E || [0x22, 0x23, 0x27, 0x3C, 0x3E].contains($0) }
    }

    private static func encodeFragment(_ s: String) -> String {
        percentEncode(s) { $0 < 0x21 || $0 > 0x7E || [0x22, 0x3C, 0x3E, 0x60].contains($0) }
    }

    private static func percentEncode(_ s: String, _ shouldEncode: (UInt8) -> Bool) -> String {
        var out = ""
        for byte in s.utf8 {
            if shouldEncode(byte) {
                out += String(format: "%%%02X", byte)
            } else {
                out.unicodeScalars.append(Unicode.Scalar(byte))
            }
        }
        return out
    }
}
