//
//  EZManhwaSourceEngine.swift
//  Ahoge
//

import Foundation

/// Reusable runtime for EZManhwa-family JSON APIs.
/// QiScans currently uses this family through https://api.qimanga.com/api/v1.
final class EZManhwaSourceEngine: SourceRuntime {
    let source: Source

    private let baseURL: String
    private let apiURL: String
    private let session: URLSession
    private let rateLimiter: SourceRateLimiter

    init(source: Source, baseURL: String, apiURL: String, requestsPerSecond: Int = 2) {
        self.source = source
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiURL = apiURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.rateLimiter = SourceRateLimiter(requestsPerSecond: requestsPerSecond)
        self.session = URLSession(
            configuration: SourceEngineUtilities.sessionConfiguration(additionalHeaders: [
                "User-Agent": SourceEngineUtilities.defaultUserAgent,
                "Accept": "application/json, text/plain, */*",
                "Referer": "\(baseURL)/",
                "Origin": baseURL
            ])
        )
    }

    func popularManga(page: Int) async throws -> [Manga] {
        try await seriesList(page: page, sort: "popular")
    }

    func latestManga(page: Int) async throws -> [Manga] {
        try await seriesList(page: page, sort: "latest")
    }

    func searchManga(_ request: SourceSearchRequest) async throws -> [Manga] {
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(max(request.page, 1))),
            URLQueryItem(name: "perPage", value: "20")
        ]

        let endpoint: String
        if query.isEmpty {
            endpoint = "/series"
            let sort = request.filters.compactMap { filter -> String? in
                if case let .sort(value) = filter { return value }
                return nil
            }.first ?? "latest"
            items.append(URLQueryItem(name: "sort", value: sort))

            if let type = request.filters.compactMap({ filter -> String? in
                if case let .types(values) = filter { return values.first }
                return nil
            }).first, !type.isEmpty {
                items.append(URLQueryItem(name: "type", value: type.uppercased()))
            }

            if let genre = request.filters.compactMap({ filter -> String? in
                if case let .genreInclude(_, slugs) = filter { return slugs.first }
                return nil
            }).first, !genre.isEmpty {
                items.append(URLQueryItem(name: "genre", value: genre))
            }
        } else {
            endpoint = "/series/search"
            items.append(URLQueryItem(name: "q", value: query))
        }

        let payload: SeriesListPayload = try await get(endpoint, queryItems: items, ttl: 60 * 10)
        return payload.data.compactMap(makeManga)
    }

    func mangaDetails(mangaIDOrURL: String) async throws -> SourceMangaDetails {
        let slug = seriesSlug(from: mangaIDOrURL)
        guard !slug.isEmpty else { throw RuntimeSourceError.mangaNotFound }
        let dto: SeriesDTO = try await get("/series/\(slug)", ttl: 60 * 30)
        guard let manga = makeManga(dto, includeDetails: true) else {
            throw RuntimeSourceError.mangaNotFound
        }
        return SourceMangaDetails(manga: manga)
    }

    func chapters(for manga: Manga) async throws -> SourceChapterDetails {
        let slug = seriesSlug(from: manga.id)
        guard !slug.isEmpty else { throw RuntimeSourceError.mangaNotFound }

        var all: [Chapter] = []
        var page = 1
        var totalPages = 1

        repeat {
            let payload: ChapterListPayload = try await get(
                "/series/\(slug)/chapters",
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "perPage", value: "100"),
                    URLQueryItem(name: "sort", value: "desc")
                ],
                ttl: 60 * 15
            )
            totalPages = max(payload.totalPages, 1)

            for chapter in payload.data where chapter.requiresPurchase != true {
                let number = chapter.number ?? -1
                let numberText = chapterNumberText(number)
                let cleanTitle = chapter.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let title: String
                if let cleanTitle, !cleanTitle.isEmpty, cleanTitle != numberText {
                    title = number >= 0 ? "Chapter \(numberText) - \(cleanTitle)" : cleanTitle
                } else {
                    title = number >= 0 ? "Chapter \(numberText)" : "Chapter"
                }

                all.append(
                    Chapter(
                        id: chapterID(seriesSlug: slug, chapterSlug: chapter.slug),
                        mangaID: manga.id,
                        title: title,
                        number: number,
                        releaseDate: parseDate(chapter.createdAt) ?? .distantPast,
                        isDownloaded: false,
                        pages: []
                    )
                )
            }
            page += 1
        } while page <= totalPages

        return SourceChapterDetails(chapters: all.sorted { $0.number > $1.number })
    }

    func pages(for chapter: Chapter) async throws -> SourcePageAsset {
        guard let identity = chapterIdentity(from: chapter.id) else {
            throw RuntimeSourceError.chapterPagesMissing
        }

        let payload: PageListPayload = try await get(
            "/series/\(identity.seriesSlug)/chapters/\(identity.chapterSlug)",
            ttl: 60 * 30
        )

        if payload.requiresPurchase == true {
            throw RuntimeSourceError.chapterPagesMissing
        }

        guard let images = payload.images, !images.isEmpty else {
            throw RuntimeSourceError.chapterPagesMissing
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
                remoteURL: absoluteURL(image.url)
            )
        }

        return SourcePageAsset(pages: pages, errorMessage: nil)
    }

    func genreTags() async throws -> [GenreTag] {
        // EZManhwa exposes genres as part of series data rather than requiring
        // them for the basic browse/reader flow. We can add a dedicated genre
        // endpoint later without blocking reading.
        []
    }

    private func seriesList(page: Int, sort: String) async throws -> [Manga] {
        let payload: SeriesListPayload = try await get(
            "/series",
            queryItems: [
                URLQueryItem(name: "page", value: String(max(page, 1))),
                URLQueryItem(name: "perPage", value: "20"),
                URLQueryItem(name: "sort", value: sort)
            ],
            ttl: 60 * 10
        )
        return payload.data.compactMap(makeManga)
    }

    private func makeManga(_ dto: SeriesDTO) -> Manga? {
        makeManga(dto, includeDetails: false)
    }

    private func makeManga(_ dto: SeriesDTO, includeDetails: Bool) -> Manga? {
        guard dto.type?.uppercased() != "NOVEL" else { return nil }
        let authorParts = [dto.author, dto.artist]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let author = Array(Set(authorParts)).joined(separator: " • ")
        let description = includeDetails
            ? SourceEngineUtilities.stripHTML(dto.description ?? "")
            : ""

        return Manga(
            id: "\(source.id)::series::\(dto.slug)",
            sourceID: source.id,
            title: dto.title,
            author: author.isEmpty ? "Unknown" : author,
            summary: description,
            genres: dto.genres?.map(\.name) ?? [],
            coverHexes: SourceEngineUtilities.palette(for: dto.slug),
            coverURL: dto.cover.map(absoluteURL),
            statusText: statusText(dto.status)
        )
    }

    private func statusText(_ value: String?) -> String {
        switch value?.uppercased() {
        case "ONGOING", "MASS_RELEASED": return "Ongoing"
        case "COMPLETED": return "Completed"
        case "DROPPED": return "Dropped"
        case "HIATUS": return "Hiatus"
        default: return "Unknown"
        }
    }

    private func seriesSlug(from value: String) -> String {
        if let url = URL(string: value), url.host != nil {
            let components = url.pathComponents.filter { $0 != "/" }
            if let index = components.firstIndex(of: "series"), components.indices.contains(index + 1) {
                return components[index + 1]
            }
        }

        let parts = value.components(separatedBy: "::")
        if let index = parts.firstIndex(of: "series"), parts.indices.contains(index + 1) {
            return parts[index + 1]
        }
        return parts.last ?? value
    }

    private func chapterID(seriesSlug: String, chapterSlug: String) -> String {
        "\(source.id)::series::\(seriesSlug)::chapter::\(chapterSlug)"
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

    private func absoluteURL(_ value: String) -> String {
        guard URL(string: value)?.scheme == nil else { return value }
        if value.hasPrefix("/") { return baseURL + value }
        return baseURL + "/" + value
    }

    private func chapterNumberText(_ value: Double) -> String {
        guard value >= 0 else { return "" }
        return value.rounded() == value ? String(Int(value)) : String(value)
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
        let key = SourceEngineUtilities.cacheKey(namespace: "ezmanhwa", request: request)
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

private struct EZManhwaSeriesListPayload: Decodable {
    let data: [EZManhwaSeriesDTO]
    let totalPages: Int
    let current: Int
}

private struct EZManhwaSeriesDTO: Decodable {
    let slug: String
    let title: String
    let cover: String?
    let type: String?
    let status: String?
    let alternativeTitles: String?
    let description: String?
    let author: String?
    let artist: String?
    let genres: [EZManhwaGenreDTO]?
}

private struct EZManhwaGenreDTO: Decodable {
    let name: String
}

private struct EZManhwaChapterListPayload: Decodable {
    let data: [EZManhwaChapterDTO]
    let totalPages: Int
    let current: Int
}

private struct EZManhwaChapterDTO: Decodable {
    let slug: String
    let number: Double?
    let title: String?
    let requiresPurchase: Bool?
    let createdAt: String?
}

private struct EZManhwaPageListPayload: Decodable {
    let images: [EZManhwaImageDTO]?
    let requiresPurchase: Bool?
    let totalImages: Int?
}

private struct EZManhwaImageDTO: Decodable {
    let url: String
}

private typealias SeriesListPayload = EZManhwaSeriesListPayload
private typealias SeriesDTO = EZManhwaSeriesDTO
private typealias ChapterListPayload = EZManhwaChapterListPayload
private typealias PageListPayload = EZManhwaPageListPayload
