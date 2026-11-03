import Foundation

enum AppInfo {
    static let name = "Ahoge"
    /// "0.5.0", what releases are compared against.
    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    static var version: String {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(shortVersion) (\(build))"
    }
}
