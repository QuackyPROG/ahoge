import Foundation

/// When the app asks for Face ID, Touch ID or the passcode again.
enum LockPolicy {
    /// Minutes the app may stay in the background before it locks: 0 locks every time, -1 never relocks.
    static let afterOptions = [0, 1, 2, 5, 10, -1]

    /// `lastActive` is when the app left the foreground; nil means it was not running (a cold launch always asks).
    static func needsUnlock(lastActive: Date?, now: Date, setting: Int) -> Bool {
        guard let lastActive else { return true }
        if setting < 0 { return false }
        return now.timeIntervalSince(lastActive) >= Double(setting) * 60
    }

    static func label(_ minutes: Int) -> String {
        switch minutes {
        case 0: "Always"
        case ..<0: "Never"
        case 1: "After 1 minute"
        default: "After \(minutes) minutes"
        }
    }
}
