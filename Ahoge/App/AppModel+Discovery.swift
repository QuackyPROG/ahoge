import Foundation

extension AppModel {
    func sourceIsEnabled(_ source: Source) -> Bool { state.sourceEnabledOverrides[source.id] ?? source.isEnabled }
    func sourceIsPinned(_ source: Source) -> Bool { state.sourcePinnedOverrides[source.id] ?? source.isPinned }
    func setSourceEnabled(_ source: Source, enabled: Bool) {
        state.sourceEnabledOverrides[source.id] = enabled
        persist()
    }
    func setSourcePinned(_ source: Source, pinned: Bool) {
        state.sourcePinnedOverrides[source.id] = pinned
        persist()
    }

    func searchSource(_ source: Source, query: String, page: Int = 1, filters: [SourceFilterValue] = []) async throws -> [Manga] {
        try Task.checkCancellation()
        if source.kind == .local {
            return page == 1 ? mangas(for: source).filter { $0.title.localizedCaseInsensitiveContains(query) } : []
        }
        guard supportsLiveSource(source) else { throw DiscoveryError.unsupported }
        let result = try await repository.searchManga(sourceID: source.id, query: query, filters: filters, page: max(page, 1))
        try Task.checkCancellation()
        return result
    }

    func sourceFeed(_ source: Source, mode: SourceFeedKind, query: String, filters: [SourceFilterValue], page: Int) async throws -> [Manga] {
        guard supportsLiveSource(source) else { throw DiscoveryError.unsupported }
        let items: [Manga]
        let descriptor = descriptor(for: source.id)
        let supported = SourceSearchFilters.supported(family: descriptor?.engineFamily, adapter: descriptor?.overrides["adapter"], query: query, baseURL: descriptor?.context?.baseURL)
        switch SourceFeedOperation.make(mode: mode, query: query, filters: filters, page: page, supported: supported) {
        case .popular(let page): items = try await repository.popularManga(sourceID: source.id, page: page)
        case .latest(let page): items = try await repository.latestManga(sourceID: source.id, page: page)
        case .search(let request): items = try await searchSource(source, query: request.query, page: request.page, filters: request.filters)
        }
        try Task.checkCancellation()
        return items
    }
}

enum DiscoveryError: LocalizedError {
    case unsupported
    var errorDescription: String? { "This source has no enabled, constructible runtime for this operation." }
}
