import Foundation

enum AppInfo {
    static let name = "Ahoge"
    /// "0.5.0 (412)", plus the commit on builds from Scripts/push-to-phone.sh.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        guard let commit = info?["AhogeCommit"] as? String else { return "\(short) (\(build))" }
        return "\(short) (\(build), \(commit))"
    }
}
