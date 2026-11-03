import Foundation

/// A Mihon/Tachiyomi backup (`.tachibk`) read into Ahoge's own `Backup`, so `BackupService.restore`
/// handles it unchanged. Only the fields Ahoge uses are read; everything else is skipped.
///
/// The file is gzip, then protobuf. Field numbers are from Mihon's `data/backup/models`.
enum MihonBackupImporter {
    struct Imported: Equatable {
        var backup: Backup
        /// Names of Mihon sources with no installed or listed Ahoge source of the same name.
        var unmatchedSources: [String]
    }

    /// `sources` are the Ahoge sources to match by name (the repositories' lists, installed or not).
    static func decode(_ data: Data, sources: [RepoSource], now: Date = Date()) throws -> Imported {
        let bytes: [UInt8]
        if data.starts(with: [0x1f, 0x8b]) {
            bytes = try Gzip.decompress([UInt8](data))
        } else {
            bytes = [UInt8](data)
        }
        let parsed: ParsedBackup
        do {
            parsed = try ParsedBackup(bytes)
        } catch {
            throw BackupError.notABackup
        }
        guard !parsed.manga.isEmpty || !parsed.categories.isEmpty || !parsed.sources.isEmpty else { throw BackupError.notABackup }
        return map(parsed, sources: sources, now: now)
    }

    // MARK: Mapping

    private static func map(_ parsed: ParsedBackup, sources: [RepoSource], now: Date) -> Imported {
        let sourceNames = Dictionary(parsed.sources.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var matches: [Int64: RepoSource?] = [:]
        func match(_ id: Int64) -> RepoSource? {
            if let cached = matches[id] { return cached }
            let found = sourceNames[id].flatMap { find($0, in: sources) }
            matches[id] = .some(found)
            return found
        }

        let categories = parsed.categories.sorted { ($0.order, $0.name) < ($1.order, $1.name) }
        var unmatched: [String] = []
        var installed: [String] = []
        var manga: [BackupManga] = []
        for item in parsed.manga {
            let name = sourceNames[item.source] ?? "Source \(item.source)"
            let sourceId: String
            if let source = match(item.source) {
                sourceId = source.id
                if !installed.contains(source.id) { installed.append(source.id) }
            } else {
                sourceId = "mihon:\(item.source)"
                if !unmatched.contains(name) { unmatched.append(name) }
            }
            let history = Dictionary(item.history.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
            manga.append(BackupManga(
                sourceId: sourceId,
                sourceName: name,
                url: item.url,
                title: item.title,
                cover: item.thumbnailUrl,
                author: item.author,
                artist: item.artist,
                summary: item.description,
                genres: item.genres,
                status: status(item.status),
                inLibrary: item.favorite,
                dateAdded: item.dateAdded > 0 ? Date(timeIntervalSince1970: Double(item.dateAdded) / 1000) : nil,
                notes: item.notes,
                categories: item.categories.compactMap { order in categories.first { $0.order == order }?.name },
                excludedScanlators: item.excludedScanlators,
                chapters: item.chapters.enumerated().map { index, chapter in
                    let entry = history[chapter.url]
                    return BackupChapter(
                        url: chapter.url,
                        name: chapter.name,
                        number: Double(chapter.number),
                        scanlator: chapter.scanlator,
                        dateUpload: chapter.dateUpload > 0 ? Date(timeIntervalSince1970: Double(chapter.dateUpload) / 1000) : nil,
                        sourceOrder: chapter.sourceOrder ?? index,
                        read: chapter.read,
                        bookmark: chapter.bookmark,
                        lastPageRead: Int(clamping: chapter.lastPageRead),
                        lastRead: entry.map { Date(timeIntervalSince1970: Double($0.lastRead) / 1000) },
                        timeRead: entry.map { Int(clamping: $0.readDuration / 1000) } ?? 0
                    )
                }
            ))
        }

        let backup = Backup(
            createdAt: now,
            manga: manga,
            categories: categories.enumerated().map { BackupCategory(name: $1.name, sort: $0) },
            installedSourceIds: installed
        )
        return Imported(backup: backup, unmatchedSources: unmatched)
    }

    /// Case-insensitive name match. Mihon's backup has no language, so with several candidates English wins.
    static func find(_ name: String, in sources: [RepoSource]) -> RepoSource? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = sources.filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(wanted) == .orderedSame }
        return candidates.first { $0.lang == "en" } ?? candidates.first
    }

    private static func status(_ value: Int) -> String {
        switch value {
        case 1: "ongoing"
        case 2, 4: "completed"
        case 3: "licensed"
        case 5: "cancelled"
        case 6: "hiatus"
        default: "unknown"
        }
    }

    // MARK: Parsing

    private struct ParsedBackup {
        var manga: [ParsedManga] = []
        var categories: [ParsedCategory] = []
        var sources: [ParsedSource] = []

        init(_ bytes: [UInt8]) throws {
            var reader = ProtoReader(bytes)
            while let (field, value) = try reader.next() {
                switch field {
                case 1: manga.append(try ParsedManga(value.lengthDelimited()))
                case 2: categories.append(try ParsedCategory(value.lengthDelimited()))
                case 101: sources.append(try ParsedSource(value.lengthDelimited()))
                default: break
                }
            }
        }
    }

    private struct ParsedManga {
        var source: Int64 = 0
        var url = ""
        var title = ""
        var artist = ""
        var author = ""
        var description = ""
        var genres: [String] = []
        var status = 0
        var thumbnailUrl = ""
        var dateAdded: Int64 = 0
        var chapters: [ParsedChapter] = []
        var categories: [Int64] = []
        var favorite = true
        var history: [ParsedHistory] = []
        var excludedScanlators: [String] = []
        var notes = ""

        init(_ bytes: [UInt8]) throws {
            var reader = ProtoReader(bytes)
            while let (field, value) = try reader.next() {
                switch field {
                case 1: source = value.int64
                case 2: url = try value.string()
                case 3: title = try value.string()
                case 4: artist = try value.string()
                case 5: author = try value.string()
                case 6: description = try value.string()
                case 7: genres.append(try value.string())
                case 8: status = Int(clamping: value.int64)
                case 9: thumbnailUrl = try value.string()
                case 13: dateAdded = value.int64
                case 16: chapters.append(try ParsedChapter(value.lengthDelimited()))
                case 17: categories.append(contentsOf: try value.varints())
                case 100: favorite = value.int64 != 0
                case 104: history.append(try ParsedHistory(value.lengthDelimited()))
                case 108: excludedScanlators.append(try value.string())
                case 110: notes = try value.string()
                default: break
                }
            }
        }
    }

    private struct ParsedChapter {
        var url = ""
        var name = ""
        var scanlator: String?
        var read = false
        var bookmark = false
        var lastPageRead: Int64 = 0
        var dateUpload: Int64 = 0
        var number: Float = 0
        /// Nil when the file omitted it (protobuf drops zero), so the list position is used.
        var sourceOrder: Int?

        init(_ bytes: [UInt8]) throws {
            var reader = ProtoReader(bytes)
            while let (field, value) = try reader.next() {
                switch field {
                case 1: url = try value.string()
                case 2: name = try value.string()
                case 3: scanlator = try value.string()
                case 4: read = value.int64 != 0
                case 5: bookmark = value.int64 != 0
                case 6: lastPageRead = value.int64
                case 8: dateUpload = value.int64
                case 9: number = try value.float()
                case 10: sourceOrder = Int(clamping: value.int64)
                default: break
                }
            }
        }
    }

    private struct ParsedCategory {
        var name = ""
        var order: Int64 = 0

        init(_ bytes: [UInt8]) throws {
            var reader = ProtoReader(bytes)
            while let (field, value) = try reader.next() {
                switch field {
                case 1: name = try value.string()
                case 2: order = value.int64
                default: break
                }
            }
        }
    }

    private struct ParsedSource {
        var name = ""
        var id: Int64 = 0

        init(_ bytes: [UInt8]) throws {
            var reader = ProtoReader(bytes)
            while let (field, value) = try reader.next() {
                switch field {
                case 1: name = try value.string()
                case 2: id = value.int64
                default: break
                }
            }
        }
    }

    private struct ParsedHistory {
        var url = ""
        var lastRead: Int64 = 0
        var readDuration: Int64 = 0

        init(_ bytes: [UInt8]) throws {
            var reader = ProtoReader(bytes)
            while let (field, value) = try reader.next() {
                switch field {
                case 1: url = try value.string()
                case 2: lastRead = value.int64
                case 3: readDuration = value.int64
                default: break
                }
            }
        }
    }
}

// MARK: - Protobuf

enum ProtoError: Error {
    case truncated
    case badWireType
    case badUTF8
}

/// One field's value, by wire type.
enum ProtoValue {
    case varint(UInt64)
    case fixed64(UInt64)
    case bytes([UInt8])
    case fixed32(UInt32)

    var int64: Int64 {
        switch self {
        case .varint(let value), .fixed64(let value): return Int64(bitPattern: value)
        case .fixed32(let value): return Int64(value)
        case .bytes: return 0
        }
    }

    func lengthDelimited() throws -> [UInt8] {
        guard case .bytes(let bytes) = self else { throw ProtoError.badWireType }
        return bytes
    }

    func string() throws -> String {
        guard let text = String(bytes: try lengthDelimited(), encoding: .utf8) else { throw ProtoError.badUTF8 }
        return text
    }

    func float() throws -> Float {
        guard case .fixed32(let bits) = self else { throw ProtoError.badWireType }
        return Float(bitPattern: bits)
    }

    /// A repeated integer field: one value per entry, or several in a packed entry.
    func varints() throws -> [Int64] {
        switch self {
        case .varint(let value): return [Int64(bitPattern: value)]
        case .bytes(let bytes):
            var reader = ProtoReader(bytes)
            var result: [Int64] = []
            while !reader.isAtEnd { result.append(Int64(bitPattern: try reader.varint())) }
            return result
        default: throw ProtoError.badWireType
        }
    }
}

/// Reads protobuf fields from a byte array: varint, length-delimited, and fixed 32/64-bit values.
struct ProtoReader {
    private let bytes: [UInt8]
    private var position = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var isAtEnd: Bool { position >= bytes.count }

    /// The next field, or nil at the end.
    mutating func next() throws -> (field: Int, value: ProtoValue)? {
        guard !isAtEnd else { return nil }
        let key = try varint()
        let field = Int(truncatingIfNeeded: key >> 3)
        guard field > 0 else { throw ProtoError.badWireType }
        switch key & 7 {
        case 0: return (field, .varint(try varint()))
        case 1: return (field, .fixed64(try fixed(8)))
        case 2:
            let length = try varint()
            guard length <= UInt64(bytes.count - position) else { throw ProtoError.truncated }
            let end = position + Int(length)
            defer { position = end }
            return (field, .bytes(Array(bytes[position..<end])))
        case 5: return (field, .fixed32(UInt32(truncatingIfNeeded: try fixed(4))))
        default: throw ProtoError.badWireType
        }
    }

    mutating func varint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while position < bytes.count {
            let byte = bytes[position]
            position += 1
            if shift < 64 { result |= UInt64(byte & 0x7f) << shift }
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        throw ProtoError.truncated
    }

    private mutating func fixed(_ count: Int) throws -> UInt64 {
        guard position + count <= bytes.count else { throw ProtoError.truncated }
        var result: UInt64 = 0
        for offset in 0..<count { result |= UInt64(bytes[position + offset]) << UInt64(8 * offset) }
        position += count
        return result
    }
}

// MARK: - Gzip

/// Gzip around raw DEFLATE, which is what `NSData.decompressed(using: .zlib)` reads.
enum Gzip {
    static func decompress(_ bytes: [UInt8]) throws -> [UInt8] {
        guard bytes.count >= 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else { throw BackupError.notABackup }
        let flags = bytes[3]
        var position = 10
        if flags & 4 != 0 {
            guard position + 2 <= bytes.count else { throw BackupError.notABackup }
            position += 2 + Int(bytes[position]) + Int(bytes[position + 1]) << 8
        }
        for flag: UInt8 in [8, 16] where flags & flag != 0 {
            while position < bytes.count, bytes[position] != 0 { position += 1 }
            position += 1
        }
        if flags & 2 != 0 { position += 2 }
        let end = bytes.count - 8
        guard position < end else { throw BackupError.notABackup }
        let deflate = Data(bytes[position..<end])
        guard let inflated = try? (deflate as NSData).decompressed(using: .zlib) else { throw BackupError.notABackup }
        return [UInt8](inflated as Data)
    }
}
