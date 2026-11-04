import Foundation
import OSLog

/// The app's own log, readable back for "Share logs".
enum AppLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.quackyprog.ahoge"
    static let logger = Logger(subsystem: subsystem, category: "app")

    /// The last `limit` lines this app logged since it launched, oldest first.
    static func recentLines(limit: Int = 500) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(at: store.position(timeIntervalSinceLatestBoot: 0), matching: NSPredicate(format: "subsystem == %@", subsystem))
        let formatter = ISO8601DateFormatter()
        let lines = entries.compactMap { $0 as? OSLogEntryLog }.map { entry in
            "\(formatter.string(from: entry.date)) [\(entry.category)] \(entry.composedMessage)"
        }
        return Array(lines.suffix(limit))
    }

    /// The log as a text file in the temporary folder, for the share sheet.
    static func exportFile() throws -> URL {
        var lines = ["Ahoge \(AppInfo.version)", ""]
        lines += try recentLines()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ahoge-log.txt")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
