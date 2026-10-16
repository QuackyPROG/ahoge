import Foundation

struct PackageInstallation: Codable, Hashable {
    var package: SourceRepoPackage
    var trusted: Bool
    var enabled: Bool
    var admissionOrder: Int
    init(package: SourceRepoPackage, trusted: Bool, enabled: Bool, admissionOrder: Int = 0) {
        self.package = package; self.trusted = trusted; self.enabled = enabled; self.admissionOrder = admissionOrder
    }
    enum CodingKeys: String, CodingKey { case package, trusted, enabled, admissionOrder }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        package = try c.decode(SourceRepoPackage.self, forKey: .package)
        trusted = try c.decodeIfPresent(Bool.self, forKey: .trusted) ?? false
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        admissionOrder = try c.decodeIfPresent(Int.self, forKey: .admissionOrder) ?? 0
    }
}

enum PackageVersion {
    static func newer(_ candidate: String, than installed: String) -> Bool {
        func parse(_ version: String) -> [Int]? {
            let value = version.hasPrefix("v") ? String(version.dropFirst()) : version
            guard !value.contains("-"), !value.contains("+") else { return nil }
            let parts = value.split(separator: ".", omittingEmptySubsequences: false)
            guard (1...3).contains(parts.count) else { return nil }
            let numbers = parts.compactMap { Int($0) }
            guard numbers.count == parts.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
            return numbers + Array(repeating: 0, count: 3 - numbers.count)
        }
        guard let lhs = parse(candidate), let rhs = parse(installed) else { return false }
        return rhs.lexicographicallyPrecedes(lhs)
    }
}

/// Runtime admission reads installed versions, while the catalog reads fetched versions.
enum PackageAdmission {
    static func records(_ records: [SourceRepoRecord], installations: [String: PackageInstallation]) -> [SourceRepoRecord] {
        let ordered = records.sorted { lhs, rhs in
            func rank(_ record: SourceRepoRecord) -> Int { installations.filter { $0.key.hasPrefix(record.id + "::") && $0.value.enabled && $0.value.trusted }.values.map(\.admissionOrder).min() ?? Int.max }
            let left = rank(lhs), right = rank(rhs)
            return left == right ? lhs.id < rhs.id : left < right
        }
        return ordered.map { record in
            let installed = installations.filter { $0.key.hasPrefix(record.id + "::") && $0.value.trusted && $0.value.enabled }
            let keys = installed.keys.sorted { left, right in
                let a = installed[left]?.admissionOrder ?? 0, b = installed[right]?.admissionOrder ?? 0
                return a == b ? left < right : a < b
            }
            let packages = keys.compactMap { installed[$0]?.package }
            return SourceRepoRecord(id: record.id, url: record.url, title: record.title, fetchedAt: record.fetchedAt,
                packages: packages, importedSources: packages.flatMap(\.sources), lastError: record.lastError)
        }
    }
}
