import Foundation

/// When this install stops opening: a free Apple ID signs apps for 7 days.
enum SigningInfo {
    /// nil when the app has no provisioning profile, as in the simulator.
    static let expiry: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return expiry(inProfile: data)
    }()

    /// A profile is a property list wrapped in a signature, so the plist is cut out of the bytes.
    static func expiry(inProfile data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.upperBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil),
              let profile = plist as? [String: Any] else { return nil }
        return profile["ExpirationDate"] as? Date
    }

    /// Under two days left: the PC re-signs well before this, so it has been missing the phone.
    static func expiresSoon(_ expiry: Date, now: Date = Date()) -> Bool {
        expiry.timeIntervalSince(now) < 2 * 24 * 60 * 60
    }
}
