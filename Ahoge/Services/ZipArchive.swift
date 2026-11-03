import Foundation

/// Just enough ZIP for comic archives: write stored (uncompressed) .cbz files and read stored or deflated ones.
/// In-house rather than ZIPFoundation, whose manifest links the host's zlib when xtool builds on Linux.
/// No ZIP64 and no encryption: chapters are far below 4 GB, and such archives are refused with an error.
enum ZipArchive {
    enum ZipError: LocalizedError {
        case notAZip
        case corrupt(String)
        case unsupported(String)
        case unsafePath(String)
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .notAZip: return "Not a ZIP archive"
            case .corrupt(let what): return "Damaged ZIP archive: \(what)"
            case .unsupported(let what): return "Unsupported ZIP archive: \(what)"
            case .unsafePath(let name): return "ZIP entry \"\(name)\" points outside its folder"
            case .tooLarge: return "Too large for a ZIP archive without ZIP64"
            }
        }
    }

    struct Entry: Equatable {
        let name: String
        var isDirectory: Bool { name.hasSuffix("/") }
        fileprivate let method: UInt16
        fileprivate let crc: UInt32
        fileprivate let compressedSize: Int
        fileprivate let size: Int
        fileprivate let headerOffset: Int
    }

    // MARK: Writing

    /// Writes `files` in order, stored without compression: pages are already compressed images.
    static func write(files: [(name: String, data: Data)], to url: URL) throws {
        guard files.count < 0xFFFF else { throw ZipError.tooLarge }
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        guard fm.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            let (time, date) = dosTimestamp(Date())
            var central = Data()
            var offset = 0
            for file in files {
                let name = Data(file.name.utf8)
                guard file.data.count < Int(UInt32.max), offset < Int(UInt32.max), name.count <= 0xFFFF else { throw ZipError.tooLarge }
                let crc = crc32(file.data)
                // The fields the local header and the central record share, from "version needed" on.
                var common = Data()
                common.append(le16(20))                   // version needed: 2.0
                common.append(le16(0x0800))               // flags: names are UTF-8
                common.append(le16(0))                    // method: stored
                common.append(le16(time))
                common.append(le16(date))
                common.append(le32(crc))
                common.append(le32(UInt32(file.data.count)))
                common.append(le32(UInt32(file.data.count)))
                common.append(le16(UInt16(name.count)))
                common.append(le16(0))                    // extra length

                var local = le32(0x0403_4B50)
                local.append(common)
                local.append(name)
                try handle.write(contentsOf: local)
                try handle.write(contentsOf: file.data)

                central.append(le32(0x0201_4B50))
                central.append(le16(20))                  // version made by
                central.append(common)
                central.append(le16(0))                   // comment length
                central.append(le16(0))                   // disk number
                central.append(le16(0))                   // internal attributes
                central.append(le32(0))                   // external attributes
                central.append(le32(UInt32(offset)))
                central.append(name)
                offset += local.count + file.data.count
            }
            guard offset + central.count < Int(UInt32.max) else { throw ZipError.tooLarge }
            var end = le32(0x0605_4B50)
            end.append(le16(0))                           // this disk
            end.append(le16(0))                           // disk with the directory
            end.append(le16(UInt16(files.count)))
            end.append(le16(UInt16(files.count)))
            end.append(le32(UInt32(central.count)))
            end.append(le32(UInt32(offset)))
            end.append(le16(0))                           // comment length
            try handle.write(contentsOf: central)
            try handle.write(contentsOf: end)
        } catch {
            try? fm.removeItem(at: url)
            throw error
        }
    }

    // MARK: Reading

    /// Every entry in the archive's central directory, folders included (their names end in "/").
    static func entries(at url: URL) throws -> [Entry] {
        try entries(in: Data(contentsOf: url, options: .alwaysMapped))
    }

    /// The bytes of one entry, checked against its CRC.
    static func extract(_ entry: Entry, from url: URL) throws -> Data {
        try extract(entry, in: Data(contentsOf: url, options: .alwaysMapped))
    }

    /// Unpacks every entry below `directory`, creating folders as needed. Refuses names that escape it.
    static func extractAll(from url: URL, to directory: URL) throws {
        let archive = try Data(contentsOf: url, options: .alwaysMapped)
        let fm = FileManager.default
        for entry in try entries(in: archive) {
            let parts = try safeComponents(entry.name)
            guard !parts.isEmpty else { continue }
            let target = parts.reduce(directory) { $0.appendingPathComponent($1) }
            if entry.isDirectory {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try extract(entry, in: archive).write(to: target)
            }
        }
    }

    /// Path parts of an entry name; throws for absolute paths and "..", which could write outside the target.
    static func safeComponents(_ name: String) throws -> [String] {
        let normalized = name.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if normalized.hasPrefix("/") || parts.contains("..") || parts.first?.contains(":") == true {
            throw ZipError.unsafePath(name)
        }
        return parts.filter { $0 != "." }
    }

    private static func entries(in data: Data) throws -> [Entry] {
        let bytes = Reader(data: data)
        // The end record is the last 22 bytes plus an optional comment of up to 64 KB.
        guard data.count >= 22 else { throw ZipError.notAZip }
        var end = data.count - 22
        let lowest = max(0, end - 0xFFFF)
        while end >= lowest, try bytes.u32(end) != 0x0605_4B50 { end -= 1 }
        guard end >= lowest else { throw ZipError.notAZip }
        let count = Int(try bytes.u16(end + 10))
        let directorySize = try bytes.u32(end + 12)
        let directoryOffset = try bytes.u32(end + 16)
        if count == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            throw ZipError.unsupported("ZIP64")
        }

        var result: [Entry] = []
        result.reserveCapacity(count)
        var cursor = Int(directoryOffset)
        for _ in 0..<count {
            guard try bytes.u32(cursor) == 0x0201_4B50 else { throw ZipError.corrupt("central directory") }
            let flags = try bytes.u16(cursor + 8)
            let nameLength = Int(try bytes.u16(cursor + 28))
            let extraLength = Int(try bytes.u16(cursor + 30))
            let commentLength = Int(try bytes.u16(cursor + 32))
            let compressed = try bytes.u32(cursor + 20)
            let size = try bytes.u32(cursor + 24)
            let offset = try bytes.u32(cursor + 42)
            if compressed == 0xFFFF_FFFF || size == 0xFFFF_FFFF || offset == 0xFFFF_FFFF {
                throw ZipError.unsupported("ZIP64")
            }
            if flags & 1 != 0 { throw ZipError.unsupported("encryption") }
            let nameBytes = try bytes.slice(cursor + 46, nameLength)
            // Bit 11 marks UTF-8; older tools wrote code page 437, which Latin-1 approximates.
            let name = String(data: nameBytes, encoding: .utf8) ?? String(data: nameBytes, encoding: .isoLatin1) ?? ""
            // Sizes come from here, not the local header, which is zero when bit 3 (data descriptor) is set.
            result.append(Entry(
                name: name,
                method: try bytes.u16(cursor + 10),
                crc: try bytes.u32(cursor + 16),
                compressedSize: Int(compressed),
                size: Int(size),
                headerOffset: Int(offset)
            ))
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return result
    }

    private static func extract(_ entry: Entry, in data: Data) throws -> Data {
        let bytes = Reader(data: data)
        guard try bytes.u32(entry.headerOffset) == 0x0403_4B50 else { throw ZipError.corrupt("local header of \(entry.name)") }
        let nameLength = Int(try bytes.u16(entry.headerOffset + 26))
        let extraLength = Int(try bytes.u16(entry.headerOffset + 28))
        let stored = try bytes.slice(entry.headerOffset + 30 + nameLength + extraLength, entry.compressedSize)
        let output: Data
        switch entry.method {
        case 0:
            output = stored
        case 8:
            if entry.size == 0 {
                output = Data()
            } else {
                // NSData's .zlib is raw DEFLATE (RFC 1951), which is what ZIP stores.
                guard let inflated = try? (stored as NSData).decompressed(using: .zlib) else {
                    throw ZipError.corrupt("deflate stream of \(entry.name)")
                }
                output = inflated as Data
            }
        default:
            throw ZipError.unsupported("compression method \(entry.method)")
        }
        guard output.count == entry.size, crc32(output) == entry.crc else { throw ZipError.corrupt("checksum of \(entry.name)") }
        return output
    }

    // MARK: Bytes

    /// Bounds-checked little-endian reads, so a truncated archive throws instead of crashing.
    private struct Reader {
        let data: Data

        func slice(_ offset: Int, _ count: Int) throws -> Data {
            guard offset >= 0, count >= 0, offset <= data.count - count else { throw ZipError.corrupt("truncated") }
            let start = data.startIndex + offset
            return data.subdata(in: start..<start + count)
        }

        func u16(_ offset: Int) throws -> UInt16 {
            let b = try slice(offset, 2)
            return UInt16(b[b.startIndex]) | UInt16(b[b.startIndex + 1]) << 8
        }

        func u32(_ offset: Int) throws -> UInt32 {
            let b = try slice(offset, 4)
            var value: UInt32 = 0
            for (shift, byte) in b.enumerated() { value |= UInt32(byte) << UInt32(8 * shift) }
            return value
        }
    }

    private static func le16(_ value: UInt16) -> Data { Data([UInt8(value & 0xFF), UInt8(value >> 8)]) }
    private static func le32(_ value: UInt32) -> Data { Data((0..<4).map { UInt8((value >> (8 * UInt32($0))) & 0xFF) }) }

    /// MS-DOS time and date fields, in local time as ZIP tools expect.
    private static func dosTimestamp(_ date: Date) -> (time: UInt16, date: UInt16) {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(0, (c.year ?? 1980) - 1980)
        let time = (c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2
        let day = year << 9 | (c.month ?? 1) << 5 | (c.day ?? 1)
        return (UInt16(truncatingIfNeeded: time), UInt16(truncatingIfNeeded: day))
    }

    private static let crcTable: [UInt32] = (0..<256).map { n in
        (0..<8).reduce(UInt32(n)) { c, _ in c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    }

    /// The standard CRC-32 (IEEE, as in ZIP and gzip).
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { buffer in
            for byte in buffer {
                crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
