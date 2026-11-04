import Foundation

/// Builds protobuf bytes for tests: just enough to write a Mihon backup by hand.
struct ProtoWriter {
    private(set) var bytes: [UInt8] = []

    private mutating func varint(_ value: UInt64) {
        var rest = value
        while rest >= 0x80 {
            bytes.append(UInt8(rest & 0x7f) | 0x80)
            rest >>= 7
        }
        bytes.append(UInt8(rest))
    }

    private mutating func key(_ field: Int, _ wireType: UInt64) { varint(UInt64(field) << 3 | wireType) }

    mutating func int(_ field: Int, _ value: Int64) {
        key(field, 0)
        varint(UInt64(bitPattern: value))
    }

    mutating func bool(_ field: Int, _ value: Bool) { int(field, value ? 1 : 0) }

    mutating func float(_ field: Int, _ value: Float) {
        key(field, 5)
        let bits = value.bitPattern
        for shift in stride(from: 0, to: 32, by: 8) { bytes.append(UInt8((bits >> UInt32(shift)) & 0xff)) }
    }

    mutating func string(_ field: Int, _ value: String) { message(field, bytes: Array(value.utf8)) }

    mutating func message(_ field: Int, bytes body: [UInt8]) {
        key(field, 2)
        varint(UInt64(body.count))
        bytes += body
    }

    mutating func message(_ field: Int, _ build: (inout ProtoWriter) -> Void) {
        var inner = ProtoWriter()
        build(&inner)
        message(field, bytes: inner.bytes)
    }

    /// Gzip framing around raw DEFLATE, as Mihon writes it. The trailer's CRC is left zero because
    /// the reader skips it.
    static func gzip(_ raw: [UInt8], fileName: String? = nil) throws -> Data {
        let deflated = try (Data(raw) as NSData).compressed(using: .zlib) as Data
        var header: [UInt8] = [0x1f, 0x8b, 8, fileName == nil ? 0 : 8, 0, 0, 0, 0, 0, 0xff]
        if let fileName { header += Array(fileName.utf8) + [0] }
        var trailer: [UInt8] = [0, 0, 0, 0]
        let size = UInt32(raw.count)
        for shift in stride(from: 0, to: 32, by: 8) { trailer.append(UInt8((size >> UInt32(shift)) & 0xff)) }
        return Data(header) + deflated + Data(trailer)
    }
}
