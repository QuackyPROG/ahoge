import CryptoKit
import Foundation

extension String {
    /// nil for an empty string, so `a.nonEmpty ?? b` falls back.
    var nonEmpty: String? { isEmpty ? nil : self }
}

extension Array where Element: Hashable {
    /// Each element once, keeping the first occurrence and the order (unique `ForEach` ids).
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension Data {
    var sha256Hex: String { SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined() }
}
