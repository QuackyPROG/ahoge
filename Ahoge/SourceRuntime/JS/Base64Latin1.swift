import Foundation

/// WHATWG atob/btoa (Latin-1). JavaScriptCore provides neither.
enum Base64Latin1 {
    struct InvalidCharacter: Error {}

    private static let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

    static func atob(_ input: String) throws -> String {
        // Filter scalars, not Characters: "\r\n" is a single Character in Swift.
        var text = String(input.unicodeScalars.filter { ![0x20, 0x09, 0x0A, 0x0C, 0x0D].contains($0.value) })
        if text.count % 4 == 0 {
            if text.hasSuffix("==") {
                text.removeLast(2)
            } else if text.hasSuffix("=") {
                text.removeLast()
            }
        }
        guard text.count % 4 != 1, text.allSatisfy({ alphabet.contains($0) }) else { throw InvalidCharacter() }
        let padded = text + String(repeating: "=", count: (4 - text.count % 4) % 4)
        guard let data = Data(base64Encoded: padded) else { throw InvalidCharacter() }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: data.map { Unicode.Scalar($0) })
        return String(view)
    }

    static func btoa(_ input: String) throws -> String {
        var bytes: [UInt8] = []
        for scalar in input.unicodeScalars {
            guard scalar.value <= 0xFF else { throw InvalidCharacter() }
            bytes.append(UInt8(scalar.value))
        }
        return Data(bytes).base64EncodedString()
    }
}
