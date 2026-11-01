import Foundation

enum SourceError: LocalizedError, Equatable {
    case cloudflare(url: String)
    case script(String)
    case timeout(String)
    case missingMethod(String)
    case decoding(String)
    case notInstalled(String)
    case noSourceAssigned

    var errorDescription: String? {
        switch self {
        case .cloudflare: return "This site needs a browser check (Cloudflare). Open it in the web view, wait for the page to load, tap Done, then retry."
        case .script(let message): return message
        case .timeout(let message): return message
        case .missingMethod(let name): return "Source does not implement \(name)"
        case .decoding(let message): return message
        case .notInstalled(let id): return "Source \(id) is not installed."
        case .noSourceAssigned: return "Script did not assign `source`"
        }
    }
}
