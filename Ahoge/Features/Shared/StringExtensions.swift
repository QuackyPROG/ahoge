import CryptoKit
import Foundation

extension String {
    /// nil for an empty string, so `a.nonEmpty ?? b` falls back.
    var nonEmpty: String? { isEmpty ? nil : self }
}

extension Data {
    var sha256Hex: String { SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined() }
}
