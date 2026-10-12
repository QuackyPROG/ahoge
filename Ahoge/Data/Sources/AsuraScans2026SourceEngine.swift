//
//  AsuraScans2026SourceEngine.swift
//  Ahoge
//

import Foundation

/// Current Asura Scans runtime for the 2026 asurascans.com stack.
/// Browse/search use the public JSON API; details, chapter discovery and free
/// chapter pages use the server-rendered website. Premium/login flows are not
/// handled here.
final class AsuraScans2026SourceEngine: SourceRuntime {
    let source: Source

    private let baseURL: String
    private let apiURL: String
    private let session: URLSession
    private let rateLimiter = SourceRateLimiter(requestsPerSecond: 1)

    init(
        source: Source,
        baseURL: String = "https://asurascans.com",
        apiURL: String = "https://api.asurascans.com/api"
    ) {
        self.source = source
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiURL = apiURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.session = URLSession(
            configuration: SourceEngineUtilities.sessionConfiguration(additionalHeaders: [
                "User-Agent": SourceEngineUtilities.defaultUserAgent,
                "Accept-Language": "en-US,en;q=0.9",
                "Accept": "application/json, text/html;q=0.9,*/*;q=0.8",
                "Referer": "\(baseURL)/"
            ])
        )
    }

    func popularManga(page: Int) async throws -> [Manga] {
        try await seriesList(page: page, query: "", sort: "popular")
    }

    func latestManga(page: Int) async throws -> [Manga] {
        try await seriesList(page: page, query: "", sort: "latest")
    }

    func searchManga(_ request: SourceSearchRequest) async throws -> [Manga] {
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sort = request.filters.compactMap { filter -> String? in
            if case let .sort(value) = filter { return value }
            return nil
        }.first ?? (query.isEmpty ? "popular" : "latest")
        let ascending = request.filters.compactMap { filter -> Bool? in
            if case let .orderAscending(value) = filter { return value }
            return nil
        }.first ?? false

        return try await seriesList(
            page: max(request.page, 1),
            query: query,
            sort: sort,
            order: ascending ? "asc" : "desc"
        )
    }

    func mangaDetails(mangaIDOrURL: String) async throws -> SourceMangaDetails {
        let identity = mangaIdentity(from: mangaIDOrURL)
        guard !identity.publicSlug.isEmpty else { throw RuntimeSourceError.mangaNotFound }

        let url = try websiteURL("/comics/\(identity.publicSlug)")
        let html = try await getHTML(url, ttl: 60 * 30)

        let rawTitle = firstHTMLMatch(
            html,
            patterns: [
                #"<h1[^>]*>([\s\S]*?)</h1>"#,
                #"<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']"#
            ]
        )
        let title = rawTitle
            .map { SourceEngineUtilities.stripHTML($0) }
            .map { $0.replacingOccurrences(of: " | Asura Scans", with: "") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let cover = firstHTMLMatch(
            html,
            patterns: [
                #"<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']"#,
                #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']"#
            ]
        )

        let description = firstHTMLMatch(
            html,
            patterns: [
                #"<meta[^>]+name=["']description["'][^>]+content=["']([^"']+)["']"#,
                #"<meta[^>]+content=["']([^"']+)["'][^>]+name=["']description["']"#
            ]
        ).map(SourceEngineUtilities.decodeHTML) ?? ""

        let status = firstHTMLMatch(
            html,
            patterns: [#"(?i)Status\s*</[^>]+>\s*<[^>]+>\s*([^<]+)"#]
        )?.trimmingCharacters(in: .whitespacesAndNewlines).capitalized ?? "Unknown"

        let manga = Manga(
            id: mangaID(slug: identity.slug, publicSlug: identity.publicSlug),
            sourceID: source.id,
            title: title ?? SourceEngineUtilities.titleFromSlug(identity.slug),
            author: "Unknown",
            summary: description,
            genres: [],
            coverHexes: SourceEngineUtilities.palette(for: identity.slug),
            coverURL: cover.map(SourceEngineUtilities.decodeHTML),
            statusText: status
        )
        return SourceMangaDetails(manga: manga)
    }

    func chapters(for manga: Manga) async throws -> SourceChapterDetails {
        let identity = mangaIdentity(from: manga.id)
        guard !identity.publicSlug.isEmpty else { throw RuntimeSourceError.mangaNotFound }

        let url = try websiteURL("/comics/\(identity.publicSlug)")
        let html = try await getHTML(url, ttl: 60 * 15)

        let pattern = #"href=["'](/comics/[^"']+/chapter/([0-9]+(?:\.[0-9]+)?))["']"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, range: range)

        var seen = Set<String>()
        var chapters: [Chapter] = []
        for match in matches {
            guard
                let pathRange = Range(match.range(at: 1), in: html),
                let numberRange = Range(match.range(at: 2), in: html)
            else { continue }

            let path = String(html[pathRange])
            guard seen.insert(path).inserted else { continue }
            let numberString = String(html[numberRange])
            let number = Double(numberString) ?? -1
            let chapterURL = baseURL + SourceEngineUtilities.decodeHTML(path)

            chapters.append(
                Chapter(
                    id: chapterURL,
                    mangaID: manga.id,
                    title: "Chapter \(numberString)",
                    number: number,
                    releaseDate: .distantPast,
                    isDownloaded: false,
                    pages: []
                )
            )
        }

        guard !chapters.isEmpty else { throw RuntimeSourceError.invalidResponse }
        return SourceChapterDetails(chapters: chapters.sorted { $0.number > $1.number })
    }

    func pages(for chapter: Chapter) async throws -> SourcePageAsset {
        guard let url = URL(string: chapter.id) else {
            throw RuntimeSourceError.chapterPagesMissing
        }
        let html = try await getHTML(url, ttl: 60 * 30)

        // Current free chapter images are served from cdn.asurascans.com under
        // /asura-images/chapters/. Restricting to this path avoids picking up
        // avatars, covers, logos and recommendation images from the page.
        let pattern = #"https://cdn\.asurascans\.com/asura-images/chapters/[^\s\"'<>\\]+"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, range: range)

        var seen = Set<String>()
        var urls: [String] = []
        for match in matches {
            guard let matchRange = Range(match.range, in: html) else { continue }
            var value = String(html[matchRange])
            value = SourceEngineUtilities.decodeHTML(value)
                .replacingOccurrences(of: "\\u0026", with: "&")
                .replacingOccurrences(of: "\\/", with: "/")
            if seen.insert(value).inserted {
                urls.append(value)
            }
        }

        guard !urls.isEmpty else { throw RuntimeSourceError.parserEmpty }
        let pages = urls.enumerated().map { index, imageURL in
            ReaderPage(
                id: "\(chapter.id)#page-\(index + 1)",
                index: index,
                title: "Page \(index + 1)",
                body: "",
                accentHex: SourceEngineUtilities.paletteColor(seed: "\(chapter.id)-\(index)"),
                assetKind: .image,
                assetPath: nil,
                remoteURL: imageURL
            )
        }
        return SourcePageAsset(pages: pages, errorMessage: nil)
    }

    func genreTags() async throws -> [GenreTag] {
        []
    }

    private func seriesList(
        page: Int,
        query: String,
        sort: String,
        order: String = "desc"
    ) async throws -> [Manga] {
        var queryItems = [
            URLQueryItem(name: "offset", value: String((max(page, 1) - 1) * 20)),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "sort", value: sort),
            URLQueryItem(name: "order", value: order)
        ]
        if !query.isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: query))
        }

        let payload: SeriesEnvelope = try await getJSON(
            "/series",
            queryItems: queryItems,
            ttl: 60 * 10
        )
        return payload.data.orEmpty.map(makeManga)
    }

    private func makeManga(_ dto: SeriesDTO) -> Manga {
        let publicSlug = URL(string: baseURL + dto.publicURL)?.pathComponents.last
            ?? dto.publicURL.split(separator: "/").last.map(String.init)
            ?? dto.slug
        return Manga(
            id: mangaID(slug: dto.slug, publicSlug: publicSlug),
            sourceID: source.id,
            title: dto.title,
            author: "Unknown",
            summary: "",
            genres: [],
            coverHexes: SourceEngineUtilities.palette(for: dto.slug),
            coverURL: dto.coverURL,
            statusText: "Unknown"
        )
    }

    private func mangaID(slug: String, publicSlug: String) -> String {
        "\(source.id)::series::\(slug)::public::\(publicSlug)"
    }

    private func mangaIdentity(from value: String) -> (slug: String, publicSlug: String) {
        if let url = URL(string: value), url.host != nil {
            let parts = url.pathComponents.filter { $0 != "/" }
            if let comicsIndex = parts.firstIndex(of: "comics"), parts.indices.contains(comicsIndex + 1) {
                let publicSlug = parts[comicsIndex + 1]
                return (stripRandomSuffix(publicSlug), publicSlug)
            }
        }

        let parts = value.components(separatedBy: "::")
        let slug: String
        if let index = parts.firstIndex(of: "series"), parts.indices.contains(index + 1) {
            slug = parts[index + 1]
        } else {
            slug = parts.last ?? value
        }

        let publicSlug: String
        if let index = parts.firstIndex(of: "public"), parts.indices.contains(index + 1) {
            publicSlug = parts[index + 1]
        } else {
            publicSlug = slug
        }
        return (slug, publicSlug)
    }

    private func stripRandomSuffix(_ slug: String) -> String {
        slug.replacingOccurrences(
            of: #"-[a-z0-9]{8}$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private func firstHTMLMatch(_ html: String, patterns: [String]) -> String? {
        for pattern in patterns {
            if let result = SourceEngineUtilities.firstMatch(
                in: html,
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ) {
                return result
            }
        }
        return nil
    }

    private func websiteURL(_ path: String) throws -> URL {
        guard let url = URL(string: baseURL + path) else {
            throw RuntimeSourceError.invalidURL
        }
        return url
    }

    private func getHTML(_ url: URL, ttl: TimeInterval) async throws -> String {
        await rateLimiter.waitTurn()
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let key = SourceEngineUtilities.cacheKey(namespace: "asura-2026-html", request: request)
        return try await SourceEngineUtilities.html(
            session: session,
            request: request,
            cacheKey: key,
            ttl: ttl
        )
    }

    private func getJSON<T: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem],
        ttl: TimeInterval
    ) async throws -> T {
        guard var components = URLComponents(string: apiURL + path) else {
            throw RuntimeSourceError.invalidURL
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw RuntimeSourceError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("\(baseURL)/", forHTTPHeaderField: "Referer")

        await rateLimiter.waitTurn()
        let key = SourceEngineUtilities.cacheKey(namespace: "asura-2026-api", request: request)
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

private struct AsuraSeriesEnvelope: Decodable {
    let data: [AsuraSeriesDTO]?
}

private struct AsuraSeriesDTO: Decodable {
    let publicURL: String
    let slug: String
    let title: String
    let coverURL: String

    private enum CodingKeys: String, CodingKey {
        case publicURL = "public_url"
        case slug
        case title
        case coverURL
        case cover
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        publicURL = try container.decode(String.self, forKey: .publicURL)
        slug = try container.decode(String.self, forKey: .slug)
        title = try container.decode(String.self, forKey: .title)
        coverURL = try container.decodeIfPresent(String.self, forKey: .coverURL)
            ?? container.decode(String.self, forKey: .cover)
    }
}

private typealias SeriesEnvelope = AsuraSeriesEnvelope
private typealias SeriesDTO = AsuraSeriesDTO

private extension Optional where Wrapped == [AsuraSeriesDTO] {
    var orEmpty: [AsuraSeriesDTO] { self ?? [] }
}
