import Foundation

struct FilterOption: Codable, Hashable {
    let value: String
    let label: String
}

struct SortValue: Codable, Hashable {
    var value: String
    var ascending: Bool
}

/// One entry of a source's `filters()` list. Unknown types are dropped when decoding a list.
indirect enum SourceFilter: Hashable {
    case header(name: String)
    case separator
    case text(key: String, name: String)
    case checkbox(key: String, name: String, defaultValue: Bool)
    case tristate(key: String, name: String)
    case select(key: String, name: String, options: [FilterOption], defaultValue: String)
    case sort(key: String, name: String, options: [FilterOption], defaultValue: SortValue)
    case group(key: String, name: String, filters: [SourceFilter])

    var key: String? {
        switch self {
        case .header, .separator: nil
        case .text(let key, _), .checkbox(let key, _, _), .tristate(let key, _), .select(let key, _, _, _),
             .sort(let key, _, _, _), .group(let key, _, _): key
        }
    }

    var name: String {
        switch self {
        case .separator: ""
        case .header(let name), .text(_, let name), .checkbox(_, let name, _), .tristate(_, let name),
             .select(_, let name, _, _), .sort(_, let name, _, _), .group(_, let name, _): name
        }
    }

    var defaultValue: FilterValue? {
        switch self {
        case .header, .separator: nil
        case .text: .text("")
        case .checkbox(_, _, let value): .bool(value)
        case .tristate: .state(.ignore)
        case .select(_, _, _, let value): .option(value)
        case .sort(_, _, _, let value): .sort(value)
        case .group(_, _, let filters): .group(SourceFilter.defaults(for: filters))
        }
    }

    static func defaults(for filters: [SourceFilter]) -> [String: FilterValue] {
        var values: [String: FilterValue] = [:]
        for filter in filters {
            if let key = filter.key, let value = filter.defaultValue { values[key] = value }
        }
        return values
    }
}

extension SourceFilter: Decodable {
    private enum CodingKeys: String, CodingKey { case type, key, name, options, filters }
    private enum DefaultKey: String, CodingKey { case `default` }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = try decoder.container(keyedBy: DefaultKey.self)
        let type = try c.decode(String.self, forKey: .type)
        let name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        func key() throws -> String { try c.decode(String.self, forKey: .key) }
        switch type {
        case "header": self = .header(name: name)
        case "separator": self = .separator
        case "text": self = .text(key: try key(), name: name)
        case "checkbox": self = .checkbox(key: try key(), name: name, defaultValue: try d.decodeIfPresent(Bool.self, forKey: .default) ?? false)
        case "tristate": self = .tristate(key: try key(), name: name)
        case "select", "sort":
            let options = try c.decode([FilterOption].self, forKey: .options)
            guard let first = options.first else { throw DecodingError.dataCorruptedError(forKey: .options, in: c, debugDescription: "no options") }
            if type == "select" {
                let value = try d.decodeIfPresent(String.self, forKey: .default)
                self = .select(key: try key(), name: name, options: options, defaultValue: value ?? first.value)
            } else {
                let value = try d.decodeIfPresent(SortValue.self, forKey: .default)
                self = .sort(key: try key(), name: name, options: options, defaultValue: value ?? SortValue(value: first.value, ascending: false))
            }
        case "group": self = .group(key: try key(), name: name, filters: try c.decode(FilterList.self, forKey: .filters).filters)
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown filter type \(type)")
        }
    }
}

/// Decodes a filter list, skipping entries this app version does not understand.
struct FilterList: Decodable {
    let filters: [SourceFilter]

    private struct Lossy: Decodable {
        let filter: SourceFilter?
        init(from decoder: Decoder) throws { filter = try? SourceFilter(from: decoder) }
    }

    init(filters: [SourceFilter]) { self.filters = filters }

    init(from decoder: Decoder) throws {
        filters = try [Lossy](from: decoder).compactMap(\.filter)
    }
}

enum TriState: Int, Codable, Hashable {
    case ignore = 0, include = 1, exclude = 2

    var next: TriState {
        switch self {
        case .ignore: .include
        case .include: .exclude
        case .exclude: .ignore
        }
    }
}

/// A filter value as the script receives it: string, bool, 0/1/2, option value, { value, ascending }, or an object.
enum FilterValue: Hashable, Encodable {
    case text(String)
    case bool(Bool)
    case state(TriState)
    case option(String)
    case sort(SortValue)
    case group([String: FilterValue])

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let v), .option(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .state(let v): try c.encode(v.rawValue)
        case .sort(let v): try c.encode(v)
        case .group(let v): try c.encode(v)
        }
    }
}

/// The user's current filter choices for one source.
struct FilterState: Equatable {
    let filters: [SourceFilter]
    var values: [String: FilterValue]

    init(filters: [SourceFilter]) {
        self.filters = filters
        values = SourceFilter.defaults(for: filters)
    }

    init(filters: [SourceFilter], values: [String: FilterValue]) {
        self.filters = filters
        self.values = values
    }

    static let empty = FilterState(filters: [])

    var isEmpty: Bool { filters.isEmpty }

    mutating func reset() { values = SourceFilter.defaults(for: filters) }

    /// How many filters differ from their defaults (each changed group child counts once).
    var activeCount: Int { Self.changes(filters, values) }

    private static func changes(_ filters: [SourceFilter], _ values: [String: FilterValue]) -> Int {
        filters.reduce(0) { total, filter in
            guard let key = filter.key, let value = values[key] else { return total }
            if case .group(_, _, let children) = filter, case .group(let inner) = value {
                return total + changes(children, inner)
            }
            return total + (value == filter.defaultValue ? 0 : 1)
        }
    }

    func json() -> String {
        let data = (try? JSONEncoder().encode(values)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// Turns on the first checkbox or tristate (at any depth) whose name matches, e.g. a genre tapped
    /// on the manga screen. Returns false when the source has no such filter.
    mutating func include(named name: String) -> Bool {
        guard let path = Self.path(to: name, in: filters) else { return false }
        values = Self.setting(path, in: values, filters: filters)
        return true
    }

    private static func path(to name: String, in filters: [SourceFilter]) -> [SourceFilter]? {
        for filter in filters {
            switch filter {
            case .checkbox, .tristate:
                if filter.name.caseInsensitiveCompare(name) == .orderedSame { return [filter] }
            case .group(_, _, let children):
                if let rest = path(to: name, in: children) { return [filter] + rest }
            default: break
            }
        }
        return nil
    }

    private static func setting(_ path: [SourceFilter], in values: [String: FilterValue], filters: [SourceFilter]) -> [String: FilterValue] {
        guard let filter = path.first, let key = filter.key else { return values }
        var values = values
        switch filter {
        case .checkbox: values[key] = .bool(true)
        case .tristate: values[key] = .state(.include)
        case .group(_, _, let children):
            let inner: [String: FilterValue]
            if case .group(let current) = values[key] { inner = current } else { inner = SourceFilter.defaults(for: children) }
            values[key] = .group(setting(Array(path.dropFirst()), in: inner, filters: children))
        default: break
        }
        return values
    }
}
