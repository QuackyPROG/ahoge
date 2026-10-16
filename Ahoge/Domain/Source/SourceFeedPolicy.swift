import Foundation

/// UI capabilities reflect compiled request parsers, not imported generic schema labels.
struct SourceSearchFilters {
    let sorts: [String]
    let ascending: Bool
    let types: Bool
    let includeGenres: Bool
    let excludeGenres: Bool
    var allowsPagination: Bool = true
    var isAvailable: Bool { !sorts.isEmpty || ascending || types || includeGenres || excludeGenres }

    static func supported(family: SourceEngineFamily?, adapter: String?, query: String, baseURL: String? = nil) -> Self {
        switch family {
        case .natsuId:
            if let baseURL, NatsuSearchQuery.deepLinkSlug(from: query, baseURL: baseURL) != nil {
                return Self(sorts: [], ascending: false, types: false, includeGenres: false, excludeGenres: false, allowsPagination: false)
            }
            return Self(sorts: ["popular", "rating", "updated", "bookmarked", "title"], ascending: true, types: true, includeGenres: true, excludeGenres: true)
        case .asuraScans:
            return Self(sorts: ["popular", "latest"], ascending: true, types: false, includeGenres: false, excludeGenres: false)
        case .mangaThemesia:
            return Self(sorts: ["popular", "update"], ascending: false, types: false, includeGenres: false, excludeGenres: false)
        case .api:
            switch adapter {
            case "mangadex":
                return Self(sorts: ["followedCount", "latestUploadedChapter", "title"], ascending: false, types: false, includeGenres: true, excludeGenres: true)
            case "weebcentral":
                return Self(sorts: ["Best Match", "Alphabet", "Popularity", "Subscribers", "Recently Added", "Latest Updates"], ascending: true, types: true, includeGenres: true, excludeGenres: true)
            case "heancms":
                return Self(sorts: ["total_views", "latest"], ascending: true, types: false, includeGenres: false, excludeGenres: false)
            // EZManhwa ignores every filter for text search and reads only the
            // first type/genre for empty queries. No general filter sheet is exposed.
            default: return .unavailable
            }
        default: return .unavailable
        }
    }

    static let unavailable = Self(sorts: [], ascending: false, types: false, includeGenres: false, excludeGenres: false)

    func applying(_ values: [SourceFilterValue]) -> [SourceFilterValue] {
        values.filter { value in
            switch value {
            case .sort(let sort): return sorts.contains(sort)
            case .orderAscending: return ascending
            case .types: return types
            case .genreInclude: return includeGenres
            case .genreExclude: return excludeGenres
            }
        }
    }
}

/// Shared by the actual dispatcher and fixtures; feed-only APIs have no filters.
enum SourceFeedOperation: Hashable {
    case popular(page: Int)
    case latest(page: Int)
    case search(SourceSearchRequest)

    static func make(mode: SourceFeedKind, query: String, filters: [SourceFilterValue], page: Int, supported: SourceSearchFilters) -> Self {
        switch mode {
        case .popular: return .popular(page: max(page, 1))
        case .latest: return .latest(page: max(page, 1))
        case .search: return .search(SourceSearchRequest(query: query, page: supported.allowsPagination ? max(page, 1) : 1, filters: supported.applying(filters)))
        }
    }
}

/// The runtime and presentation policy must classify precisely the same URLs.
/// Preserve Natsu's host/path matching, including nested paths and query strings.
enum NatsuSearchQuery {
    static func deepLinkSlug(from query: String, baseURL: String) -> String? {
        guard
            let url = URL(string: query.trimmingCharacters(in: .whitespacesAndNewlines)),
            let base = URL(string: baseURL),
            url.host == base.host
        else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, parts[0] == "manga" else { return nil }
        return parts[1]
    }
}
