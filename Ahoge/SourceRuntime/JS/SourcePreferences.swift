import Foundation

/// A stored source setting: a switch or a string (a list choice or typed text).
enum SourcePreferenceValue: Codable, Equatable {
    case bool(Bool)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }
}

/// One entry of a source's `preferences()` schema (proposed host API v2, Docs/host-api-v2-preferences.md).
struct SourcePreference: Decodable, Identifiable {
    enum Kind: String {
        case toggle, list, text
        /// A type this app doesn't know yet; the form leaves it out.
        case unsupported
    }

    struct Option: Decodable, Hashable {
        let value: String
        let title: String
    }

    let key: String
    let kind: Kind
    let title: String
    let summary: String?
    let options: [Option]
    let defaultValue: SourcePreferenceValue?
    var id: String { key }

    private enum CodingKeys: String, CodingKey {
        case key, type, title, summary, options
        case defaultValue = "default"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        kind = Kind(rawValue: try c.decode(String.self, forKey: .type)) ?? .unsupported
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? key
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        options = try c.decodeIfPresent([Option].self, forKey: .options) ?? []
        defaultValue = try? c.decodeIfPresent(SourcePreferenceValue.self, forKey: .defaultValue)
    }
}

/// Saved source settings, one JSON object per source id in UserDefaults. Only values the user
/// changed are kept; a source falls back to its own defaults for the rest.
enum SourcePreferenceStore {
    static func name(for sourceId: String) -> String { "source.prefs." + sourceId }

    static func values(for sourceId: String, in defaults: UserDefaults = .standard) -> [String: SourcePreferenceValue] {
        guard let text = defaults.string(forKey: name(for: sourceId)),
              let values = try? JSONDecoder().decode([String: SourcePreferenceValue].self, from: Data(text.utf8)) else { return [:] }
        return values
    }

    static func set(_ value: SourcePreferenceValue, for key: String, sourceId: String, in defaults: UserDefaults = .standard) {
        var values = values(for: sourceId, in: defaults)
        values[key] = value
        guard let data = try? JSONEncoder().encode(values) else { return }
        defaults.set(String(decoding: data, as: UTF8.self), forKey: name(for: sourceId))
    }

    /// The object handed to the script as `this.prefs`.
    static func json(for sourceId: String, in defaults: UserDefaults = .standard) -> String {
        guard let data = try? JSONEncoder().encode(values(for: sourceId, in: defaults)) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
