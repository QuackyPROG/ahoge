import Foundation

// Codable accepts duplicate object keys by choosing a value. A portable restore
// must reject that ambiguity before decoding any selected section.
enum BackupJSONValidation {
    static func validate(_ data: Data) throws {
        var parser = Parser(bytes: Array(data))
        try parser.value(depth: 0)
        parser.whitespace()
        guard parser.index == parser.bytes.count else { throw BackupError.invalid("Unexpected trailing backup content.") }
    }
    private struct Parser {
        let bytes: [UInt8]
        var index = 0
        mutating func whitespace() { while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
        mutating func take(_ byte: UInt8) throws { whitespace(); guard index < bytes.count, bytes[index] == byte else { throw BackupError.invalid("Malformed backup JSON.") }; index += 1 }
        mutating func string() throws -> String {
            whitespace(); let start = index; try take(34)
            var escaped = false
            while index < bytes.count {
                let byte = bytes[index]; index += 1
                if byte == 34 && !escaped { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) }
                if byte == 92 && !escaped { escaped = true } else { escaped = false }
            }
            throw BackupError.invalid("Unterminated backup string.")
        }
        mutating func value(depth: Int) throws {
            guard depth < 128 else { throw BackupError.invalid("Backup nesting exceeds safety limit.") }
            whitespace(); guard index < bytes.count else { throw BackupError.invalid("Missing backup value.") }
            switch bytes[index] {
            case 123:
                index += 1; whitespace(); var keys = Set<String>()
                if index < bytes.count && bytes[index] == 125 { index += 1; return }
                while true {
                    let key = try string()
                    guard keys.insert(key).inserted else { throw BackupError.invalid("Duplicate backup object key: " + key) }
                    try take(58); try value(depth: depth + 1); whitespace()
                    guard index < bytes.count else { throw BackupError.invalid("Unclosed backup object.") }
                    if bytes[index] == 125 { index += 1; return }
                    try take(44)
                }
            case 91:
                index += 1; whitespace()
                if index < bytes.count && bytes[index] == 93 { index += 1; return }
                while true {
                    try value(depth: depth + 1); whitespace()
                    guard index < bytes.count else { throw BackupError.invalid("Unclosed backup array.") }
                    if bytes[index] == 93 { index += 1; return }
                    try take(44)
                }
            case 34: _ = try string()
            default:
                let start = index
                while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
                guard index > start else { throw BackupError.invalid("Malformed backup value.") }
            }
        }
    }
}
