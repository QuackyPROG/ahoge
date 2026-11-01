import Foundation

struct RepoIndex: Codable, Equatable {
    let schema: Int
    let name: String
    let sources: [RepoSource]
}

struct RepoSource: Codable, Hashable, Identifiable {
    struct Health: Codable, Hashable {
        let status: String
        let checkedAt: String?
    }

    let id: String
    let name: String
    let lang: String
    let version: String
    let runtime: Int
    let nsfw: Bool
    let baseUrl: String
    let icon: String?
    let script: String
    let sha256: String
    let health: Health

    /// Only "broken" is shown as a warning; "unverified" and "unknown" are treated as usable.
    var isReportedBroken: Bool { health.status == "broken" }
}

struct ExtensionRepo: Codable, Hashable, Identifiable {
    let url: String
    var name: String
    var id: String { url }
}

struct InstalledSource: Codable, Hashable, Identifiable {
    let id: String
    var repoURL: String
    var name: String
    var lang: String
    var version: String
    var nsfw: Bool
    var baseUrl: String
    var iconURL: String?
    var sha256: String
}

enum ExtensionState: Equatable {
    case available, installed, updateAvailable, requiresAppUpdate
}

struct ExtensionRow: Identifiable, Equatable {
    let source: RepoSource
    let repoURL: String
    let iconURL: String?
    let state: ExtensionState
    var id: String { source.id }
}

enum RepoError: LocalizedError, Equatable {
    case invalidURL(String)
    case http(Int, String)
    case invalidIndex(String)
    case checksumMismatch(String)
    case requiresNewerApp(String)
    case duplicate(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "Not a valid repository URL: \(url)"
        case .http(let status, let url): return "HTTP \(status) for \(url)"
        case .invalidIndex(let reason): return "Not an Ahoge repository index: \(reason)"
        case .checksumMismatch(let id): return "The downloaded script for \(id) doesn't match the repository checksum, so it was not installed."
        case .requiresNewerApp(let id): return "\(id) needs a newer version of Ahoge."
        case .duplicate(let url): return "\(url) is already added."
        }
    }
}
