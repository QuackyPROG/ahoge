//
//  HeanCMSSourceEngine.swift
//  Ahoge
//

import Foundation

/// Reusable runtime for HeanCMS-family sources such as Omega Scans.
final class HeanCMSSourceEngine: SourceRuntime {
    let source: Source

    private let baseURL: String
    private let apiURL: String
    private let session: URLSession
    private let rateLimiter: SourceRateLimiter

    init(source: Source, baseURL: String, apiURL: String, requestsPerSecond: Int = 1) {
        self.source = source
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiURL = apiURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.rateLimiter = SourceRateLimiter(requestsPerSecond: requestsPerSecond)
        self.session = URLSession(
            configuration: SourceEngineUtilities.sessionConfiguration(additionalHeaders: [
                "User-Agent": SourceEngineUtilities.defaultUserAgent,
                "Accept": "application/json, text/plain, */*",
                "Referer": "\(baseURL)/"
            ])
        )
    }

    func popularManga(page: Int) async throws -> [Manga] {
        try await querySeries(page: page, query: "", order: "desc", orderBy: "total_views")
    }

    func latestManga(page: Int) async throws -> [Manga] {
        try await querySeries(page: page, query: "", order: "desc", orderBy: "latest")
    }

    func searchManga(_ request: SourceSearchRequest) async throws -> [Manga] {
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sort = request.filters.compactMap { filter -> String? in
            if case let .sort(value) = filter { return value }
            return nil
        }.first ?? "total_views"
        let ascending = request.filters.compactMap { filter -> Bool? in
            if case let .orderAscending(value) = filter { return value }
            return nil
        }.first ?? false

        return try await querySeries(
            page: max(request.page, 1),
            query: query,
            order: ascending ? "asc" : "desc",
            orderBy: sort
        )
    }

    func mangaDetails(mangaIDOrURL: String) async throws -> SourceMangaDetails {
        let identity = seriesIdentity(from: mangaIDOrURL)
        guard !identity.slug.isEmpty else { throw RuntimeSourceError.mangaNotFound }

        let dto: SeriesDTO = try await get("/series/\(identity.slug)", ttl: 60 * 30)
        return SourceMangaDetails(manga: makeManga(dto, includeDetails: true))
    }

    func chapters(for manga: Manga) async throws -> SourceChapterDetails {
        var identity = seriesIdentity(from: manga.id)
        if identity.id == nil {
            let dto: SeriesDTO = try await get("/series/\(identity.slug)", ttl: 60 * 30)
            identity = (dto.slug, dto.id)
        }
        guard let seriesID = identity.id else { throw RuntimeSourceError.invalidResponse }

        var all: [Chapter] = []
        var page = 1
        var lastPage = 1

        repeat {
            let payload: ChapterListPayload = try await get(
                "/chapter/query",
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "perPage", value: "1000"),
                    URLQueryItem(name: "series_id", value: String(seriesID))
                ],
                ttl: 60 * 15
            )
            lastPage = max(payload.meta.lastPage, 1)

            for dto in payload.data where (dto.price ?? 0) == 0 {
                let number = chapterNumber(from: dto.name)
                let title = dto.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayTitle = title.map { $0.isEmpty ? dto.name : "\(dto.name) - \($0)" } ?? dto.name

                all.append(
                    Chapter(
                        id: chapterID(
                            seriesSlug: identity.slug,
                            chapterSlug: dto.slug,
                            chapterID: dto.id
                        ),
                        mangaID: manga.id,
                        title: displayTitle,
                        number: number,
                        releaseDate: parseDate(dto.createdAt) ?? .distantPast,
                        isDownloaded: false,
                        pages: []
                    )
                )
            }
            page += 1
        } while page <= lastPage

        return SourceChapterDetails(chapters: all.sorted { $0.number > $1.number })
    }

    func pages(for chapter: Chapter) async throws -> SourcePageAsset {
        guard let identity = chapterIdentity(from: chapter.id) else {
            throw RuntimeSourceError.chapterPagesMissing
        }

        let payload: PagePayload = try await get(
            "/chapter/\(identity.seriesSlug)/\(identity.chapterSlug)",
            ttl: 60 * 30
        )

        guard let images = payload.chapter.chapterData?.images, !images.isEmpty else {
            if payload.paywall == true {
                throw RuntimeSourceError.chapterPagesMissing
            }
            throw RuntimeSourceError.parserEmpty
        }

        let pages = images.enumerated().map { index, image in
            ReaderPage(
                id: "\(chapter.id)::page::\(index + 1)",
                index: index,
                title: "Page \(index + 1)",
                body: "",
                accentHex: SourceEngineUtilities.paletteColor(seed: "\(chapter.id)-\(index)"),
                assetKind: .image,
                assetPath: nil,
                remoteURL: absoluteURL(image)
            )
        }

        return SourcePageAsset(pages: pages, errorMessage: nil)
    }

    func genreTags() async throws -> [GenreTag] {
        let tags: [GenreDTO] = try await get("/tags", ttl: 60 * 60 * 6)
        return tags.map { GenreTag(name: $0.name, slug: String($0.id)) }
    }

    private func querySeries(
        page: Int,
        query: String,
        order: String,
        orderBy: String
    ) async throws -> [Manga] {
        let payload: QueryPayload = try await get(
            "/query",
            queryItems: [
                URLQueryItem(name: "query_string", value: query),
                URLQueryItem(name: "status", value: "All"),
                URLQueryItem(name: "order", value: order),
                URLQueryItem(name: "orderBy", value: orderBy),
                URLQueryItem(name: "series_type", value: "Comic"),
                URLQueryItem(name: "page", value: String(max(page, 1))),
                URLQueryItem(name: "perPage", value: "12"),
                URLQueryItem(name: "tags_ids", value: "[]"),
                URLQueryItem(name: "adult", value: "true")
            ],
            ttl: 60 * 10
        )
        return payload.data.map { makeManga($0, includeDetails: false) }
    }

    private func makeManga(_ dto: SeriesDTO, includeDetails: Bool) -> Manga {
        let authorParts = [dto.author, dto.studio]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let author = Array(Set(authorParts)).joined(separator: " • ")

        return Manga(
            id: mangaID(slug: dto.slug, id: dto.id),
            sourceID: source.id,
            title: dto.title,
            author: author.isEmpty ? "Unknown" : author,
            summary: includeDetails ? SourceEngineUtilities.stripHTML(dto.description ?? "") : "",
            genres: (dto.tags ?? []).map(\.name),
            coverHexes: SourceEngineUtilities.palette(for: dto.slug),
            coverURL: absoluteURL(dto.thumbnail),
            statusText: statusText(dto.status)
        )
    }

    private func mangaID(slug: String, id: Int) -> String {
        "\(source.id)::series::\(slug)::id::\(id)"
    }

    private func seriesIdentity(from value: String) -> (slug: String, id: Int?) {
        if let url = URL(string: value), url.host != nil {
            let components = url.pathComponents.filter { $0 != "/" }
            if let index = components.firstIndex(of: "series"), components.indices.contains(index + 1) {
                return (components[index + 1], nil)
            }
        }

        let parts = value.components(separatedBy: "::")
        let slug: String
        if let seriesIndex = parts.firstIndex(of: "series"), parts.indices.contains(seriesIndex + 1) {
            slug = parts[seriesIndex + 1]
        } else {
            slug = parts.last ?? value
        }

        var id: Int?
        if let idIndex = parts.firstIndex(of: "id"), parts.indices.contains(idIndex + 1) {
            id = Int(parts[idIndex + 1])
        }
        return (slug, id)
    }

    private func chapterID(seriesSlug: String, chapterSlug: String, chapterID: Int) -> String {
        "\(source.id)::series::\(seriesSlug)::chapter::\(chapterSlug)::id::\(chapterID)"
    }

    private func chapterIdentity(from value: String) -> (seriesSlug: String, chapterSlug: String)? {
        let parts = value.components(separatedBy: "::")
        guard
            let seriesIndex = parts.firstIndex(of: "series"),
            let chapterIndex = parts.firstIndex(of: "chapter"),
            parts.indices.contains(seriesIndex + 1),
            parts.indices.contains(chapterIndex + 1)
        else { return nil }
        return (parts[seriesIndex + 1], parts[chapterIndex + 1])
    }

    private func chapterNumber(from name: String) -> Double {
        guard let text = SourceEngineUtilities.firstMatch(in: name, pattern: #"([0-9]+(?:\.[0-9]+)?)"#) else {
            return -1
        }
        return Double(text) ?? -1
    }

    private func statusText(_ value: String?) -> String {
        switch value?.lowercased() {
        case "ongoing": return "Ongoing"
        case "hiatus": return "Hiatus"
        case "dropped", "canceled", "cancelled": return "Dropped"
        case "completed", "finished": return "Completed"
        default: return "Unknown"
        }
    }

    private func absoluteURL(_ value: String) -> String {
        guard !value.isEmpty else { return value }
        if URL(string: value)?.scheme != nil { return value }
        if value.hasPrefix("/") { return apiURL + value }
        return apiURL + "/" + value
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    private func get<T: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        ttl: TimeInterval
    ) async throws -> T {
        guard var components = URLComponents(string: apiURL + path) else {
            throw RuntimeSourceError.invalidURL
        }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw RuntimeSourceError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("\(baseURL)/", forHTTPHeaderField: "Referer")

        await rateLimiter.waitTurn()
        let key = SourceEngineUtilities.cacheKey(namespace: "heancms", request: request)
        let data = try await SourceEngineUtilities.data(
            session: session,
            request: request,
            cacheKey: key,
            ttl: ttl,
            retryCount: 1,
            acceptedContentTypes: ["application/json", "text/json"]
        )

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw RuntimeSourceError.invalidResponse
        }
    }
}

private struct HeanCMSQueryPayload: Decodable {
    let data: [HeanCMSSeriesDTO]
    let meta: HeanCMSQueryMetaDTO?
}

private struct HeanCMSQueryMetaDTO: Decodable {
    let currentPage: Int
    let lastPage: Int

    enum CodingKeys: String, CodingKey {
        case currentPage = "current_page"
        case lastPage = "last_page"
    }
}

private struct HeanCMSSeriesDTO: Decodable {
    let id: Int
    let slug: String
    let author: String?
    let description: String?
    let studio: String?
    let status: String?
    let thumbnail: String
    let title: String
    let tags: [HeanCMSTagDTO]?

    enum CodingKeys: String, CodingKey {
        case id
        case slug = "series_slug"
        case author
        case description
        case studio
        case status
        case thumbnail
        case title
        case tags
    }
}

private struct HeanCMSTagDTO: Decodable {
    let id: Int?
    let name: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
    }
}

private struct HeanCMSChapterListPayload: Decodable {
    let data: [HeanCMSChapterDTO]
    let meta: HeanCMSChapterMetaDTO
}

private struct HeanCMSChapterMetaDTO: Decodable {
    let currentPage: Int
    let lastPage: Int

    enum CodingKeys: String, CodingKey {
        case currentPage = "current_page"
        case lastPage = "last_page"
    }
}

private struct HeanCMSChapterDTO: Decodable {
    let id: Int
    let name: String
    let title: String?
    let slug: String
    let createdAt: String?
    let price: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name = "chapter_name"
        case title = "chapter_title"
        case slug = "chapter_slug"
        case createdAt = "created_at"
        case price
    }
}

private struct HeanCMSPagePayload: Decodable {
    let chapter: HeanCMSPageDTO
    let paywall: Bool?
}

private struct HeanCMSPageDTO: Decodable {
    let chapterData: HeanCMSPageDataDTO?

    enum CodingKeys: String, CodingKey {
        case chapterData = "chapter_data"
    }
}

private struct HeanCMSPageDataDTO: Decodable {
    let images: [String]?
}

private struct HeanCMSGenreDTO: Decodable {
    let id: Int
    let name: String
}

private typealias QueryPayload = HeanCMSQueryPayload
private typealias SeriesDTO = HeanCMSSeriesDTO
private typealias ChapterListPayload = HeanCMSChapterListPayload
private typealias PagePayload = HeanCMSPagePayload
private typealias GenreDTO = HeanCMSGenreDTO
