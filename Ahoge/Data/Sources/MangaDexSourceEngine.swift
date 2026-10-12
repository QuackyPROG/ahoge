//
//  MangaDexSourceEngine.swift
//  Ahoge
//

import Foundation

/// Native, unauthenticated MangaDex v5 runtime.
///
/// This adapter intentionally implements only the public reading surface Ahoge needs:
/// browse, search, details, translated chapter feeds, MangaDex@Home page metadata,
/// and tags. It does not import account/session features or execute remote code.
final class MangaDexSourceEngine: SourceRuntime {
    let source: Source

    private let baseURL: String
    private let apiURL: String
    private let translatedLanguage: String
    private let session: URLSession
    private let rateLimiter: SourceRateLimiter

    init(
        source: Source,
        baseURL: String,
        apiURL: String = "https://api.mangadex.org",
        translatedLanguage: String = "en",
        requestsPerSecond: Int = 3
    ) {
        self.source = source
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiURL = apiURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.translatedLanguage = translatedLanguage
        self.rateLimiter = SourceRateLimiter(requestsPerSecond: requestsPerSecond)
        self.session = URLSession(
            configuration: SourceEngineUtilities.sessionConfiguration(additionalHeaders: [
                "User-Agent": SourceEngineUtilities.defaultUserAgent,
                "Accept": "application/json",
                "Referer": "\(baseURL)/"
            ])
        )
    }

    func popularManga(page: Int) async throws -> [Manga] {
        try await mangaList(
            page: page,
            extra: [URLQueryItem(name: "order[followedCount]", value: "desc")]
        )
    }

    func latestManga(page: Int) async throws -> [Manga] {
        try await mangaList(
            page: page,
            extra: [URLQueryItem(name: "order[latestUploadedChapter]", value: "desc")]
        )
    }

    func searchManga(_ request: SourceSearchRequest) async throws -> [Manga] {
        var extra: [URLQueryItem] = []
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            extra.append(URLQueryItem(name: "title", value: query))
            extra.append(URLQueryItem(name: "order[relevance]", value: "desc"))
        }

        if let sort = request.filters.compactMap({ value -> String? in
            if case let .sort(sort) = value { return sort }
            return nil
        }).first, !sort.isEmpty {
            extra.removeAll { $0.name.hasPrefix("order[") }
            extra.append(URLQueryItem(name: "order[\(sort)]", value: "desc"))
        }

        let includedGenres = request.filters.compactMap { value -> [String]? in
            if case let .genreInclude(_, slugs) = value { return slugs }
            return nil
        }.flatMap { $0 }
        for genre in includedGenres where !genre.isEmpty {
            extra.append(URLQueryItem(name: "includedTags[]", value: genre))
        }

        let excludedGenres = request.filters.compactMap { value -> [String]? in
            if case let .genreExclude(_, slugs) = value { return slugs }
            return nil
        }.flatMap { $0 }
        for genre in excludedGenres where !genre.isEmpty {
            extra.append(URLQueryItem(name: "excludedTags[]", value: genre))
        }

        return try await mangaList(page: request.page, extra: extra)
    }

    func mangaDetails(mangaIDOrURL: String) async throws -> SourceMangaDetails {
        guard let id = mangaUUID(from: mangaIDOrURL) else {
            throw RuntimeSourceError.mangaNotFound
        }

        let payload: MangaDexSingle<MangaDexMangaAttributes> = try await get(
            "/manga/\(id)",
            queryItems: [
                URLQueryItem(name: "includes[]", value: "cover_art"),
                URLQueryItem(name: "includes[]", value: "author"),
                URLQueryItem(name: "includes[]", value: "artist")
            ],
            ttl: 60 * 30
        )

        return SourceMangaDetails(manga: makeManga(payload.data, includeDetails: true))
    }

    func chapters(for manga: Manga) async throws -> SourceChapterDetails {
        guard let mangaID = mangaUUID(from: manga.id) else {
            throw RuntimeSourceError.mangaNotFound
        }

        let limit = 100
        var offset = 0
        var chapters: [Chapter] = []

        while true {
            let payload: MangaDexCollection<MangaDexChapterAttributes> = try await get(
                "/manga/\(mangaID)/feed",
                queryItems: [
                    URLQueryItem(name: "translatedLanguage[]", value: translatedLanguage),
                    URLQueryItem(name: "order[volume]", value: "desc"),
                    URLQueryItem(name: "order[chapter]", value: "desc"),
                    URLQueryItem(name: "includeFuturePublishAt", value: "0"),
                    URLQueryItem(name: "includeExternalUrl", value: "0"),
                    URLQueryItem(name: "includeEmptyPages", value: "0"),
                    URLQueryItem(name: "limit", value: String(limit)),
                    URLQueryItem(name: "offset", value: String(offset))
                ],
                ttl: 60 * 15
            )

            chapters.append(contentsOf: payload.data.compactMap { entity in
                guard entity.attributes.externalUrl == nil else { return nil }
                let number = Double(entity.attributes.chapter ?? "") ?? -1
                let chapterLabel = chapterNumberText(number)
                let cleanTitle = entity.attributes.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let title: String
                if let cleanTitle, !cleanTitle.isEmpty {
                    title = number >= 0 ? "Chapter \(chapterLabel) - \(cleanTitle)" : cleanTitle
                } else {
                    title = number >= 0 ? "Chapter \(chapterLabel)" : "Chapter"
                }

                return Chapter(
                    id: "\(source.id)::chapter::\(entity.id)",
                    mangaID: manga.id,
                    title: title,
                    number: number,
                    releaseDate: parseDate(entity.attributes.readableAt ?? entity.attributes.publishAt) ?? .distantPast,
                    isDownloaded: false,
                    pages: []
                )
            })

            offset += payload.limit
            if offset >= payload.total || payload.data.isEmpty { break }
        }

        return SourceChapterDetails(chapters: chapters)
    }

    func pages(for chapter: Chapter) async throws -> SourcePageAsset {
        guard let chapterID = chapterUUID(from: chapter.id) else {
            throw RuntimeSourceError.chapterPagesMissing
        }

        let payload: MangaDexAtHomeResponse = try await get(
            "/at-home/server/\(chapterID)",
            ttl: 60 * 10
        )

        guard !payload.chapter.data.isEmpty else {
            throw RuntimeSourceError.chapterPagesMissing
        }

        let host = payload.baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let pages = payload.chapter.data.enumerated().map { index, filename in
            ReaderPage(
                id: "\(chapter.id)::page::\(index + 1)",
                index: index,
                title: "Page \(index + 1)",
                body: "",
                accentHex: SourceEngineUtilities.paletteColor(seed: "\(chapter.id)-\(index)"),
                assetKind: .image,
                assetPath: nil,
                remoteURL: "\(host)/data/\(payload.chapter.hash)/\(filename)"
            )
        }

        return SourcePageAsset(pages: pages, errorMessage: nil)
    }

    func genreTags() async throws -> [GenreTag] {
        let payload: MangaDexTagCollection = try await get("/manga/tag", ttl: 60 * 60 * 12)
        return payload.data.compactMap { tag in
            guard let name = localized(tag.attributes.name), !name.isEmpty else { return nil }
            return GenreTag(name: name, slug: tag.id)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func mangaList(page: Int, extra: [URLQueryItem]) async throws -> [Manga] {
        let limit = 24
        let offset = (max(page, 1) - 1) * limit
        var items = baseMangaQueryItems(limit: limit, offset: offset)
        items.append(contentsOf: extra)

        let payload: MangaDexCollection<MangaDexMangaAttributes> = try await get(
            "/manga",
            queryItems: items,
            ttl: 60 * 10
        )
        return payload.data.map { makeManga($0, includeDetails: false) }
    }

    private func baseMangaQueryItems(limit: Int, offset: Int) -> [URLQueryItem] {
        [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "includes[]", value: "cover_art"),
            URLQueryItem(name: "availableTranslatedLanguage[]", value: translatedLanguage),
            URLQueryItem(name: "contentRating[]", value: "safe"),
            URLQueryItem(name: "contentRating[]", value: "suggestive"),
            URLQueryItem(name: "contentRating[]", value: "erotica")
        ]
    }

    private func makeManga(
        _ entity: MangaDexEntity<MangaDexMangaAttributes>,
        includeDetails: Bool
    ) -> Manga {
        let attributes = entity.attributes
        let title = localized(attributes.title) ?? attributes.title.values.first ?? "Untitled"
        let description = includeDetails ? (localized(attributes.description ?? [:]) ?? "") : ""
        let genres = attributes.tags.compactMap { localized($0.attributes.name) }
        let coverFile = entity.relationships?.first(where: { $0.type == "cover_art" })?.attributes?.fileName
        let coverURL = coverFile.map {
            "https://uploads.mangadex.org/covers/\(entity.id)/\($0).256.jpg"
        }

        let people = entity.relationships?.compactMap { relationship -> String? in
            guard relationship.type == "author" || relationship.type == "artist" else { return nil }
            return relationship.attributes?.name
        } ?? []
        let author = Array(Set(people.filter { !$0.isEmpty })).joined(separator: " • ")

        return Manga(
            id: "\(source.id)::manga::\(entity.id)",
            sourceID: source.id,
            title: title,
            author: author.isEmpty ? "Unknown" : author,
            summary: description,
            genres: genres,
            coverHexes: SourceEngineUtilities.palette(for: entity.id),
            coverURL: coverURL,
            statusText: statusText(attributes.status)
        )
    }

    private func localized(_ values: [String: String]) -> String? {
        values[translatedLanguage]
            ?? values["en"]
            ?? values.values.first
    }

    private func statusText(_ value: String?) -> String {
        switch value?.lowercased() {
        case "ongoing": return "Ongoing"
        case "completed": return "Completed"
        case "hiatus": return "Hiatus"
        case "cancelled": return "Cancelled"
        default: return "Unknown"
        }
    }

    private func mangaUUID(from value: String) -> String? {
        if let uuid = firstUUID(in: value) { return uuid }
        let parts = value.components(separatedBy: "::")
        if let index = parts.firstIndex(of: "manga"), parts.indices.contains(index + 1) {
            return parts[index + 1]
        }
        return nil
    }

    private func chapterUUID(from value: String) -> String? {
        if let uuid = firstUUID(in: value) { return uuid }
        let parts = value.components(separatedBy: "::")
        if let index = parts.firstIndex(of: "chapter"), parts.indices.contains(index + 1) {
            return parts[index + 1]
        }
        return nil
    }

    private func firstUUID(in value: String) -> String? {
        let pattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              let swiftRange = Range(match.range, in: value)
        else { return nil }
        return String(value[swiftRange]).lowercased()
    }

    private func chapterNumberText(_ value: Double) -> String {
        guard value >= 0 else { return "" }
        return value.rounded() == value ? String(Int(value)) : String(value)
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = fractional.date(from: value) { return parsed }
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
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("\(baseURL)/", forHTTPHeaderField: "Referer")

        await rateLimiter.waitTurn()
        let key = SourceEngineUtilities.cacheKey(namespace: "mangadex", request: request)
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

private struct MangaDexCollection<Attributes: Decodable>: Decodable {
    let data: [MangaDexEntity<Attributes>]
    let limit: Int
    let offset: Int
    let total: Int
}

private struct MangaDexSingle<Attributes: Decodable>: Decodable {
    let data: MangaDexEntity<Attributes>
}

private struct MangaDexEntity<Attributes: Decodable>: Decodable {
    let id: String
    let type: String
    let attributes: Attributes
    let relationships: [MangaDexRelationship]?
}

private struct MangaDexRelationship: Decodable {
    let id: String
    let type: String
    let attributes: MangaDexRelationshipAttributes?
}

private struct MangaDexRelationshipAttributes: Decodable {
    let fileName: String?
    let name: String?
}

private struct MangaDexMangaAttributes: Decodable {
    let title: [String: String]
    let description: [String: String]?
    let status: String?
    let contentRating: String?
    let tags: [MangaDexTag]
}

private struct MangaDexTagCollection: Decodable {
    let data: [MangaDexTag]
}

private struct MangaDexTag: Decodable {
    let id: String
    let type: String
    let attributes: MangaDexTagAttributes
}

private struct MangaDexTagAttributes: Decodable {
    let name: [String: String]
}

private struct MangaDexChapterAttributes: Decodable {
    let volume: String?
    let chapter: String?
    let title: String?
    let translatedLanguage: String?
    let externalUrl: String?
    let publishAt: String?
    let readableAt: String?
    let pages: Int?
}

private struct MangaDexAtHomeResponse: Decodable {
    let baseUrl: String
    let chapter: MangaDexAtHomeChapter
}

private struct MangaDexAtHomeChapter: Decodable {
    let hash: String
    let data: [String]
    let dataSaver: [String]
}
