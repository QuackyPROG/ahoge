//
//  MangaBoxSourceEngine.swift
//  Ahoge
//

import Foundation

/// Reusable native runtime for MangaBox-family sites (Manganato/NatoManga and
/// compatible mirrors). It intentionally implements the common family surface
/// instead of binding the app to one mirror's branding.
final class MangaBoxSourceEngine: SourceRuntime {
    let source: Source

    private let baseURL: String
    private let session: URLSession
    private let rateLimiter: SourceRateLimiter

    init(source: Source, baseURL: String, requestsPerSecond: Int = 2) {
        self.source = source
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.rateLimiter = SourceRateLimiter(requestsPerSecond: requestsPerSecond)
        self.session = URLSession(
            configuration: SourceEngineUtilities.sessionConfiguration(additionalHeaders: [
                "User-Agent": SourceEngineUtilities.defaultUserAgent,
                "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
                "Accept-Language": "en-US,en;q=0.9",
                "Referer": "\(baseURL)/"
            ])
        )
    }

    func popularManga(page: Int) async throws -> [Manga] {
        try await list(path: "/manga-list/hot-manga", page: page)
    }

    func latestManga(page: Int) async throws -> [Manga] {
        try await list(path: "/manga-list/latest-manga", page: page)
    }

    func searchManga(_ request: SourceSearchRequest) async throws -> [Manga] {
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return try await latestManga(page: request.page)
        }
        let normalized = normalizeSearchQuery(query)
        return try await list(path: "/search/story/\(normalized)", page: request.page)
    }

    func mangaDetails(mangaIDOrURL: String) async throws -> SourceMangaDetails {
        let slug = mangaSlug(from: mangaIDOrURL)
        guard !slug.isEmpty else { throw RuntimeSourceError.mangaNotFound }
        let html = try await getHTML(try websiteURL("/manga/\(slug)"), ttl: 60 * 30)

        let titleRaw = firstMatch(
            html,
            patterns: [
                #"<(?:h1|h2)[^>]*>([\s\S]*?)</(?:h1|h2)>"#,
                #"<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']"#
            ]
        )
        let title = titleRaw
            .map { SourceEngineUtilities.stripHTML($0) }
            .map { $0.replacingOccurrences(of: " Manga Online", with: "") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let cover = firstMatch(
            html,
            patterns: [
                #"<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']"#,
                #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']"#
            ]
        )

        let authorBlock = firstMatch(
            html,
            patterns: [
                #"(?i)Author\(s\)[\s\S]{0,300}?<td[^>]*>([\s\S]*?)</td>"#,
                #"(?i)Author[^<]*</[^>]+>[\s\S]{0,200}?<[^>]+>([\s\S]*?)</[^>]+>"#
            ]
        )
        let author = authorBlock
            .map { SourceEngineUtilities.stripHTML($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let description = firstMatch(
            html,
            patterns: [
                #"<div[^>]+id=["'](?:noidungm|panel-story-info-description|contentBox)["'][^>]*>([\s\S]*?)</div>"#,
                #"<meta[^>]+name=["']description["'][^>]+content=["']([^"']+)["']"#
            ]
        ).map(SourceEngineUtilities.stripHTML) ?? ""

        let status = firstMatch(
            html,
            patterns: [#"(?i)Status\s*:?\s*</[^>]+>[\s\S]{0,100}?<[^>]+>([^<]+)"#]
        )?.trimmingCharacters(in: .whitespacesAndNewlines).capitalized ?? "Unknown"

        let genreMatches = SourceEngineUtilities.allMatchesWithGroups(
            in: html,
            pattern: #"<a[^>]+href=["'][^"']*/genre/[^"']+["'][^>]*>([\s\S]*?)</a>"#,
            groupCount: 1
        )
        let genres = Array(Set(genreMatches.compactMap { group -> String? in
            guard let first = group.first else { return nil }
            let value = SourceEngineUtilities.stripHTML(first).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        })).sorted()

        return SourceMangaDetails(
            manga: Manga(
                id: mangaID(slug),
                sourceID: source.id,
                title: (title?.isEmpty == false) ? title! : SourceEngineUtilities.titleFromSlug(slug),
                author: (author?.isEmpty == false) ? author! : "Unknown",
                summary: description,
                genres: genres,
                coverHexes: SourceEngineUtilities.palette(for: slug),
                coverURL: cover.map(SourceEngineUtilities.decodeHTML),
                statusText: status
            )
        )
    }

    func chapters(for manga: Manga) async throws -> SourceChapterDetails {
        let slug = mangaSlug(from: manga.id)
        guard !slug.isEmpty else { throw RuntimeSourceError.mangaNotFound }

        let payload: MangaBoxChapterEnvelope = try await getJSON(
            "/api/manga/\(slug)/chapters",
            queryItems: [URLQueryItem(name: "limit", value: "-1")],
            ttl: 60 * 15
        )
        guard payload.success else { throw RuntimeSourceError.invalidResponse }

        let iso = ISO8601DateFormatter()
        let chapters = payload.data?.chapters.compactMap { dto -> Chapter? in
            guard let chapterSlug = dto.chapterSlug else { return nil }
            let number = dto.chapterNum ?? chapterNumber(from: dto.chapterName ?? chapterSlug)
            let numberText = chapterNumberText(number)
            let name = dto.chapterName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (name?.isEmpty == false) ? name! : "Chapter \(numberText)"

            return Chapter(
                id: "\(baseURL)/manga/\(slug)/\(chapterSlug)",
                mangaID: manga.id,
                title: title,
                number: number,
                releaseDate: dto.updatedAt.flatMap { iso.date(from: $0) } ?? .distantPast,
                isDownloaded: false,
                pages: []
            )
        } ?? []

        return SourceChapterDetails(chapters: chapters.sorted { $0.number > $1.number })
    }

    func pages(for chapter: Chapter) async throws -> SourcePageAsset {
        guard let url = URL(string: chapter.id) else { throw RuntimeSourceError.invalidURL }
        let html = try await getHTML(url, ttl: 60 * 30)

        // Newer MangaBox mirrors expose CDN roots + relative page paths in JS.
        // Prefer that representation because it avoids UI/decorative images.
        let cdns = scriptArray(named: "cdns", in: html) + scriptArray(named: "backupImage", in: html)
        let imagePaths = scriptArray(named: "chapterImages", in: html)

        var urls: [String] = []
        if let cdn = cdns.first, !imagePaths.isEmpty {
            let root = cdn.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            urls = imagePaths.map { path in
                let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                return "\(root)/\(clean)"
            }
        } else {
            // Older mirrors render chapter images directly inside this reader
            // container. Extract only that block to avoid covers and site UI.
            let readerBlock = firstMatch(
                html,
                patterns: [#"<div[^>]+class=["'][^"']*container-chapter-reader[^"']*["'][^>]*>([\s\S]*?)</div>"#]
            ) ?? html
            let imageGroups = SourceEngineUtilities.allMatchesWithGroups(
                in: readerBlock,
                pattern: #"<img[^>]+(?:data-src|src)=["']([^"']+)["'][^>]*>"#,
                groupCount: 1
            )
            urls = imageGroups.compactMap { $0.first }.map(absoluteURL)
        }

        var seen = Set<String>()
        let unique = urls
            .map { SourceEngineUtilities.decodeHTML($0).replacingOccurrences(of: "\\/", with: "/") }
            .filter { !$0.isEmpty && seen.insert($0).inserted }

        guard !unique.isEmpty else { throw RuntimeSourceError.parserEmpty }
        let pages = unique.enumerated().map { index, imageURL in
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

    private func list(path: String, page: Int) async throws -> [Manga] {
        guard var components = URLComponents(string: baseURL + path) else {
            throw RuntimeSourceError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "page", value: String(max(page, 1)))]
        guard let url = components.url else { throw RuntimeSourceError.invalidURL }
        let html = try await getHTML(url, ttl: 60 * 10)

        // The common MangaBox list/search templates link titles through h3/a.
        // We deliberately keep the parser tolerant of absolute or relative URLs.
        let pattern = #"<h3[^>]*>[\s\S]*?<a[^>]+href=["'](?:https?://[^/"']+)?/manga/([^"'?#/]+)[^"']*["'][^>]*>([\s\S]*?)</a>[\s\S]*?</h3>"#
        let groups = SourceEngineUtilities.allMatchesWithGroups(in: html, pattern: pattern, groupCount: 2)

        var seen = Set<String>()
        var mangas: [Manga] = []
        for group in groups {
            guard group.count == 2 else { continue }
            let slug = group[0].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !slug.isEmpty, seen.insert(slug).inserted else { continue }
            let title = SourceEngineUtilities.stripHTML(group[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            mangas.append(
                Manga(
                    id: mangaID(slug),
                    sourceID: source.id,
                    title: title,
                    author: "Unknown",
                    summary: "",
                    genres: [],
                    coverHexes: SourceEngineUtilities.palette(for: slug),
                    coverURL: nil,
                    statusText: "Unknown"
                )
            )
        }

        guard !mangas.isEmpty else { throw RuntimeSourceError.parserEmpty }
        return mangas
    }

    private func mangaID(_ slug: String) -> String {
        "\(source.id)::manga::\(slug)"
    }

    private func mangaSlug(from value: String) -> String {
        if let url = URL(string: value), url.host != nil {
            let parts = url.pathComponents.filter { $0 != "/" }
            if let index = parts.firstIndex(of: "manga"), parts.indices.contains(index + 1) {
                return parts[index + 1]
            }
        }
        let parts = value.components(separatedBy: "::")
        if let index = parts.firstIndex(of: "manga"), parts.indices.contains(index + 1) {
            return parts[index + 1]
        }
        return parts.last ?? value
    }

    private func normalizeSearchQuery(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private func chapterNumber(from value: String) -> Double {
        guard let number = SourceEngineUtilities.firstMatch(in: value, pattern: #"([0-9]+(?:\.[0-9]+)?)"#) else {
            return -1
        }
        return Double(number) ?? -1
    }

    private func chapterNumberText(_ value: Double) -> String {
        guard value >= 0 else { return "" }
        return value.rounded() == value ? String(Int(value)) : String(value)
    }

    private func scriptArray(named name: String, in html: String) -> [String] {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        guard let body = SourceEngineUtilities.firstMatch(
            in: html,
            pattern: "\\b\(escapedName)\\s*=\\s*\\[([^]]+)\\]",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }

        let groups = SourceEngineUtilities.allMatchesWithGroups(
            in: body,
            pattern: #"["']([^"']+)["']"#,
            groupCount: 1
        )
        return groups.compactMap { $0.first }
    }

    private func absoluteURL(_ value: String) -> String {
        if URL(string: value)?.scheme != nil { return value }
        if value.hasPrefix("//") { return "https:" + value }
        if value.hasPrefix("/") { return baseURL + value }
        return baseURL + "/" + value
    }

    private func firstMatch(_ html: String, patterns: [String]) -> String? {
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
        guard let url = URL(string: baseURL + path) else { throw RuntimeSourceError.invalidURL }
        return url
    }

    private func getHTML(_ url: URL, ttl: TimeInterval) async throws -> String {
        await rateLimiter.waitTurn()
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let key = SourceEngineUtilities.cacheKey(namespace: "mangabox-html", request: request)
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
        guard var components = URLComponents(string: baseURL + path) else {
            throw RuntimeSourceError.invalidURL
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw RuntimeSourceError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")

        await rateLimiter.waitTurn()
        let key = SourceEngineUtilities.cacheKey(namespace: "mangabox-api", request: request)
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

private struct MangaBoxChapterEnvelope: Decodable {
    let success: Bool
    let data: MangaBoxChapterData?
}

private struct MangaBoxChapterData: Decodable {
    let chapters: [MangaBoxChapterDTO]
}

private struct MangaBoxChapterDTO: Decodable {
    let chapterName: String?
    let chapterSlug: String?
    let chapterNum: Double?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case chapterName = "chapter_name"
        case chapterSlug = "chapter_slug"
        case chapterNum = "chapter_num"
        case updatedAt = "updated_at"
    }
}
