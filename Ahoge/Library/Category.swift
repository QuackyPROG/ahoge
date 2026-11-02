import GRDB

/// A user-made Library shelf (Mihon's category). Library titles in none of them show under "Default".
struct MangaCategory: Identifiable, Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "category"

    var id: Int64
    var name: String
    var sort: Int
}

/// A category's box in "Set categories" when several titles are edited at once.
enum CategoryCheck: Equatable {
    case on, off, mixed
}

enum CategoryAssignment {
    /// `on` when every title has the category, `mixed` when only some do.
    static func initial(categoryIds: [Int64], selections: [Set<Int64>]) -> [Int64: CategoryCheck] {
        Dictionary(uniqueKeysWithValues: categoryIds.map { id in
            let count = selections.filter { $0.contains(id) }.count
            return (id, count == 0 ? .off : count == selections.count ? .on : .mixed)
        })
    }

    /// A title's categories after saving; `mixed` leaves each title as it was.
    static func apply(_ checks: [Int64: CategoryCheck], to current: Set<Int64>) -> Set<Int64> {
        var result = current
        for (id, check) in checks {
            switch check {
            case .on: result.insert(id)
            case .off: result.remove(id)
            case .mixed: break
            }
        }
        return result
    }

    static func toggled(_ check: CategoryCheck) -> CategoryCheck { check == .on ? .off : .on }
}
