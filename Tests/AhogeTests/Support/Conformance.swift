import Foundation
import XCTest

private final class BundleToken {}

/// Loads runtime/host-api-conformance.json from ahoge-extension (copied by Scripts/sync-conformance.sh).
enum Conformance {
    static func url() -> URL? {
        Bundle(for: BundleToken.self).url(forResource: "host-api-conformance", withExtension: "json")
    }

    static func load() throws -> [String: Any] {
        let file = try XCTUnwrap(url())
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    }

    /// Compares a Swift result with a JSON `expected` value (string, integer or boolean).
    static func matches(_ actual: Any, _ expected: Any?) -> Bool {
        if let number = expected as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return (actual as? Bool) == number.boolValue }
            return (actual as? Int) == number.intValue
        }
        if let string = expected as? String { return (actual as? String) == string }
        return false
    }
}
