import Foundation

/// A preference as stored in a backup. `Pref` values are all one of these.
enum PreferenceValue: Codable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case strings([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Bool first: JSONDecoder refuses to read a number as Bool, so 1 stays an Int.
        if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String].self) { self = .strings(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported preference value") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .strings(let value): try container.encode(value)
        }
    }
}

/// Everything restored from a file: the library, categories, repositories, installed sources and settings.
/// Field names are the on-disk format (version 1); `backup-v1.json` in the tests pins them.
struct Backup: Codable, Equatable {
    static let currentVersion = 1

    var version: Int = Backup.currentVersion
    var createdAt: Date
    /// Library titles, plus other titles that have read chapters.
    var manga: [BackupManga] = []
    var categories: [BackupCategory] = []
    var repos: [String] = []
    var installedSourceIds: [String] = []
    /// Only keys listed in `Pref.backupNames`; never cookies.
    var preferences: [String: PreferenceValue] = [:]
}

struct BackupManga: Codable, Equatable {
    var sourceId: String
    /// The source's display name when the backup knows it (a Mihon import), so a report can name it.
    var sourceName: String?
    var url: String
    var title: String
    var cover: String = ""
    var author: String = ""
    var artist: String = ""
    var summary: String = ""
    var genres: [String] = []
    var status: String = "unknown"
    var inLibrary: Bool = true
    var dateAdded: Date?
    var notes: String = ""
    var updateInterval: Int?
    /// Names, because category ids differ between devices.
    var categories: [String] = []
    var excludedScanlators: [String] = []
    var chapters: [BackupChapter] = []
}

struct BackupChapter: Codable, Equatable {
    var url: String
    var name: String
    var number: Double = 0
    var scanlator: String?
    var dateUpload: Date?
    /// Position in the source's list (0 is the newest).
    var sourceOrder: Int = 0
    var read: Bool = false
    var bookmark: Bool = false
    var lastPageRead: Int = 0
    /// History: when this chapter was last read.
    var lastRead: Date?
    /// History: seconds spent reading.
    var timeRead: Int = 0
}

struct BackupCategory: Codable, Equatable {
    var name: String
    /// Position among the categories.
    var sort: Int
    var flags: Int = 0
    var sortMode: String?
}

enum BackupError: LocalizedError, Equatable {
    case notABackup
    case newerVersion(Int)

    var errorDescription: String? {
        switch self {
        case .notABackup: return "This file is not an Ahoge or Mihon backup."
        case .newerVersion(let version): return "This backup was made by a newer version of Ahoge (format \(version)). Update the app to restore it."
        }
    }
}

/// The `.ahbk` file format: the magic `AHBK1`, then the backup as zlib-compressed JSON.
enum BackupCodec {
    private static let magic = Data("AHBK1".utf8)

    static func encode(_ backup: Backup) throws -> Data {
        let json = try JSONEncoder.backup.encode(backup)
        let packed = try (json as NSData).compressed(using: .zlib) as Data
        return magic + packed
    }

    static func decode(_ data: Data) throws -> Backup {
        guard data.starts(with: magic), let json = try? (data.dropFirst(magic.count) as NSData).decompressed(using: .zlib) as Data else {
            throw BackupError.notABackup
        }
        return try decodePayload(json)
    }

    /// The JSON inside the frame. Separate so a plain-JSON golden file can protect the field names.
    static func decodePayload(_ json: Data) throws -> Backup {
        struct Header: Decodable { let version: Int }
        guard let header = try? JSONDecoder().decode(Header.self, from: json) else { throw BackupError.notABackup }
        if header.version > Backup.currentVersion { throw BackupError.newerVersion(header.version) }
        do {
            return try JSONDecoder.backup.decode(Backup.self, from: json)
        } catch {
            throw BackupError.notABackup
        }
    }
}

private extension JSONEncoder {
    static var backup: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var backup: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
