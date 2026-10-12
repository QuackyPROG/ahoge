//
//  RuntimeSourceRepository.swift
//  Ahoge
//

import Foundation

final class RuntimeSourceRepository: SourceRepository, SourceCatalogRuntime {
    private let fallback: InternalSourceRepository
    private let sourcesData: [Source]
    private let descriptorData: [SourceDescriptor]
    private let runtimes: [String: any SourceRuntime]
    private let cache: AppCacheManaging

    init(
        repoRecords: [SourceRepoRecord] = [],
        fallback: InternalSourceRepository = InternalSourceRepository(),
        cache: AppCacheManaging = AppCacheController.shared
    ) {
        self.fallback = fallback
        self.cache = cache

        // Do not expose any of the upstream bundled web sources. They are
        // legacy/sample definitions and many of their endpoints are stale.
        // Keep Local Files because it is a reader utility, not a web source.
        // Every remote source must now come from a user-imported repository.
        let localSources = fallback.sources().filter { $0.kind == .local }
        let localSourceIDs = Set(localSources.map(\.id))
        let localDescriptors = fallback.descriptors().filter {
            localSourceIDs.contains($0.sourceID)
        }

        let registry = SourceRegistryBuilder().build(
            internalSources: localSources,
            internalDescriptors: localDescriptors,
            repoRecords: repoRecords
        )
        self.sourcesData = registry.0
        self.descriptorData = registry.1
        self.runtimes = Self.buildRuntimes(sources: registry.0, descriptors: registry.1)
    }

    func sources() -> [Source] {
        sourcesData
    }

    func descriptors() -> [SourceDescriptor] {
        descriptorData
    }

    func descriptor(for sourceID: String) -> SourceDescriptor? {
        descriptorData.first { $0.sourceID == sourceID }
    }

    func mangas(for sourceID: String) -> [Manga] {
        fallback.mangas(for: sourceID)
    }

    func chapters(for mangaID: String) -> [Chapter] {
        fallback.chapters(for: mangaID)
    }

    func activeSources() -> [Source] {
        sourcesData.filter(\.isEnabled)
    }

    func popularManga(sourceID: String) async throws -> [Manga] {
        guard let runtime = runtimes[sourceID] else {
            return try await fallback.popularManga(sourceID: sourceID)
        }
        let key = "source|\(sourceID)|popular|page=1"
        return try await cache.value(for: key, domain: .sourceMetadata, policy: .returnCacheElseLoad, ttl: 60 * 15) {
            try await runtime.popularManga(page: 1)
        }
    }

    func latestManga(sourceID: String) async throws -> [Manga] {
        guard let runtime = runtimes[sourceID] else {
            return try await fallback.latestManga(sourceID: sourceID)
        }
        let key = "source|\(sourceID)|latest|page=1"
        return try await cache.value(for: key, domain: .sourceMetadata, policy: .returnCacheElseLoad, ttl: 60 * 15) {
            try await runtime.latestManga(page: 1)
        }
    }

    func searchManga(sourceID: String, query: String, filters: [SourceFilterValue]) async throws -> [Manga] {
        guard let runtime = runtimes[sourceID] else {
            return try await fallback.searchManga(sourceID: sourceID, query: query, filters: filters)
        }
        let request = SourceSearchRequest(query: query, page: 1, filters: filters)
        let key = "source|\(sourceID)|search|\(query.lowercased())|\(filters.map(\.cacheKey).joined(separator: "|"))"
        return try await cache.value(for: key, domain: .sourceMetadata, policy: .returnCacheElseLoad, ttl: 60 * 10) {
            try await runtime.searchManga(request)
        }
    }

    func mangaDetails(sourceID: String, mangaIDOrURL: String) async throws -> SourceMangaDetails {
        guard let runtime = runtimes[sourceID] else {
            return try await fallback.mangaDetails(sourceID: sourceID, mangaIDOrURL: mangaIDOrURL)
        }
        let key = "source|\(sourceID)|details|\(mangaIDOrURL)"
        let manga = try await cache.value(for: key, domain: .sourceMetadata, policy: .returnCacheElseLoad, ttl: 60 * 60) {
            try await runtime.mangaDetails(mangaIDOrURL: mangaIDOrURL).manga
        }
        return SourceMangaDetails(manga: manga)
    }

    func chapters(sourceID: String, manga: Manga) async throws -> SourceChapterDetails {
        guard let runtime = runtimes[sourceID] else {
            return try await fallback.chapters(sourceID: sourceID, manga: manga)
        }
        let key = "source|\(sourceID)|chapters|\(manga.id)"
        let chapters = try await cache.value(for: key, domain: .sourceMetadata, policy: .returnCacheElseLoad, ttl: 60 * 30) {
            try await runtime.chapters(for: manga).chapters
        }
        return SourceChapterDetails(chapters: chapters)
    }

    func pages(sourceID: String, chapter: Chapter) async throws -> SourcePageAsset {
        guard let runtime = runtimes[sourceID] else {
            return try await fallback.pages(sourceID: sourceID, chapter: chapter)
        }
        let pageKey = "source|\(sourceID)|pages|\(chapter.id)"
        let pages = try await cache.value(for: pageKey, domain: .sourceMetadata, policy: .returnCacheElseLoad, ttl: 60 * 30) {
            try await runtime.pages(for: chapter).pages
        }
        return SourcePageAsset(pages: pages, errorMessage: nil)
    }

    func genreTags(sourceID: String) async throws -> [GenreTag] {
        guard let runtime = runtimes[sourceID] else {
            return try await fallback.genreTags(sourceID: sourceID)
        }
        let key = "source|\(sourceID)|genres"
        return try await cache.value(for: key, domain: .sourceMetadata, policy: .returnCacheElseLoad, ttl: 60 * 60 * 6) {
            try await runtime.genreTags()
        }
    }

    private static func buildRuntimes(
        sources: [Source],
        descriptors: [SourceDescriptor]
    ) -> [String: any SourceRuntime] {
        var runtimes: [String: any SourceRuntime] = [:]

        for descriptor in descriptors {
            guard let source = sources.first(where: { $0.id == descriptor.sourceID }) else {
                continue
            }

            switch descriptor.engineFamily {
            case .natsuId:
                guard let context = descriptor.context else { continue }
                let chapterListPageOverride = descriptor.overrides["chapterListPageOverride"].flatMap(Int.init)
                runtimes[source.id] = NatsuIdSourceEngine(
                    configuration: NatsuIdSourceConfiguration(
                        source: source,
                        baseURL: context.baseURL,
                        rateLimit: max(context.requestPolicy.rateLimit, 1),
                        chapterListPageOverride: chapterListPageOverride
                    )
                )

            case .asuraScans:
                guard
                    let context = descriptor.context,
                    let apiURL = descriptor.overrides["apiURL"],
                    !context.baseURL.isEmpty,
                    !apiURL.isEmpty
                else { continue }
                runtimes[source.id] = AsuraScans2026SourceEngine(
                    source: source,
                    baseURL: context.baseURL,
                    apiURL: apiURL
                )

            case .api:
                guard
                    let adapter = descriptor.overrides["adapter"],
                    let context = descriptor.context,
                    let apiURL = descriptor.overrides["apiURL"]
                else { continue }

                switch adapter {
                case "ezmanhwa":
                    runtimes[source.id] = EZManhwaSourceEngine(
                        source: source,
                        baseURL: context.baseURL,
                        apiURL: apiURL,
                        requestsPerSecond: max(context.requestPolicy.rateLimit, 1)
                    )
                case "heancms":
                    runtimes[source.id] = HeanCMSSourceEngine(
                        source: source,
                        baseURL: context.baseURL,
                        apiURL: apiURL,
                        requestsPerSecond: max(context.requestPolicy.rateLimit, 1),
                        latestSortOrder: descriptor.overrides["latestSortOrder"] ?? "desc"
                    )
                default:
                    continue
                }

            case .mangaBox:
                guard
                    descriptor.overrides["adapter"] == "mangabox",
                    let context = descriptor.context
                else { continue }
                runtimes[source.id] = MangaBoxSourceEngine(
                    source: source,
                    baseURL: context.baseURL,
                    requestsPerSecond: max(context.requestPolicy.rateLimit, 1)
                )

            default:
                continue
            }
        }

        return runtimes
    }
}

private extension SourceFilterValue {
    var cacheKey: String {
        switch self {
        case .sort(let value):
            return "sort=\(value)"
        case .orderAscending(let value):
            return "asc=\(value)"
        case .types(let values):
            return "types=\(values.joined(separator: ","))"
        case .genreInclude(let mode, let slugs):
            return "include=\(mode):\(slugs.joined(separator: ","))"
        case .genreExclude(let mode, let slugs):
            return "exclude=\(mode):\(slugs.joined(separator: ","))"
        }
    }
}
