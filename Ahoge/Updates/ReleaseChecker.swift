import Foundation

/// A published GitHub release of Ahoge.
struct ReleaseInfo: Equatable, Identifiable {
    /// The tag without a leading "v".
    let version: String
    /// Markdown.
    let notes: String
    let pageURL: URL
    var id: String { version }
}

/// Looks for a newer release on GitHub (Releases are where the tag-triggered workflow publishes the IPA).
struct ReleaseChecker {
    enum CheckError: Error, LocalizedError {
        case badResponse(Int)
        var errorDescription: String? {
            switch self {
            case .badResponse(let status): "GitHub answered with status \(status)."
            }
        }
    }

    let transport: any HTTPTransport
    static let repository = "QuackyPROG/ahoge"

    private static func url(_ path: String) -> URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/\(path)")!
    }

    /// The newest release when it is newer than `current` and is not `skipped`; nil otherwise.
    func latest(current: String, skipping skipped: String? = nil) async throws -> ReleaseInfo? {
        guard let release = try await fetch(Self.url("latest")) else { return nil }
        guard Self.isNewer(release.version, than: current), release.version != Self.normalized(skipped ?? "") else { return nil }
        return release
    }

    /// The release published for `version` (its "What's new"), nil when there is none.
    func release(for version: String) async throws -> ReleaseInfo? {
        try await fetch(Self.url("tags/v\(Self.normalized(version))"))
    }

    private func fetch(_ url: URL) async throws -> ReleaseInfo? {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Ahoge", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport.send(request)
        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200 else { throw CheckError.badResponse(response.statusCode) }
        struct Payload: Decodable {
            let tag_name: String
            let body: String?
            let html_url: URL
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return ReleaseInfo(version: Self.normalized(payload.tag_name), notes: payload.body ?? "", pageURL: payload.html_url)
    }

    /// "v1.2.3" and "1.2.3" are the same version.
    static func normalized(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespaces)
        return trimmed.lowercased().hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
    }

    /// Semantic versions: numbers compared part by part ("0.10.0" is newer than "0.9.0"); with equal
    /// numbers a release is newer than its own pre-release ("0.5.0" over "0.5.0-beta").
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let (a, aPre) = parse(candidate)
        let (b, bPre) = parse(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return !aPre.isEmpty ? false : !bPre.isEmpty
    }

    private static func parse(_ version: String) -> (numbers: [Int], preRelease: String) {
        let core = normalized(version).split(separator: "+", maxSplits: 1).first.map(String.init) ?? ""
        let parts = core.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = (parts.first ?? "").split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        return (numbers, parts.count > 1 ? String(parts[1]) : "")
    }
}
