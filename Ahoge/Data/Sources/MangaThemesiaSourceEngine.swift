// Modified for Ahoge from the documented behavior of Apache-2.0-licensed
// Keiyoushi MangaThemesia extensions. See THIRD_PARTY_NOTICES.md.

import Foundation

/// Common-subset runtime for MangaThemesia/WPMangaStream-family sites.
///
/// This intentionally supports only ordinary server-rendered MangaThemesia
/// pages. Alternate/random-domain variants, image scrambling, browser
/// challenges, authentication, and executable remote logic are out of scope.
final class MangaThemesiaSourceEngine: SourceRuntime {
    let source: Source

    private let baseURL: String
    private let mangaPath: String
    private let dateFormat: String
    private let session: URLSession
    private let rateLimiter: SourceRateLimiter

    init(
        source: Source,
        baseURL: String,
        requestsPerSecond: Int = 2,
        mangaPath: String = "manga",
        dateFormat: String = "MMMM d, yyyy"
    ) {
        self.source = source
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.mangaPath = mangaPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.dateFormat = dateFormat
        self.rateLimiter = SourceRateLimiter(requestsPerSecond: requestsPerSecond)
        self.session = URLSession(
            configuration: SourceEngineUtilities.sessionConfiguration(additionalHeaders: [
                "User-Agent": SourceEngineUtilities.defaultUserAgent,
                "Accept": "text/html,application/xhtml+xml;q=0.9,*/*;q=0.8",
                "Accept-Language": "en-US,en;q=0.9",
                "Referer": "\(baseURL)/"
            ])
        )
    }

    func popularManga(page: Int) async throws -> [Manga] {
        try await list(page: page, query: "", order: "popular")
    }

    func latestManga(page: Int) async throws -> [Manga] {
        try await list(page: page, query: "", order: "update")
    }

    func searchManga(_ request: SourceSearchRequest) async throws -> [Manga] {
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let order = request.filters.compactMap { filter -> String? in
            if case let .sort(value) = filter { return value }
            return nil
        }.last
        return try await list(page: max(request.page, 1), query: query, order: order)
    }

    func mangaDetails(mangaIDOrURL: String) async throws -> SourceMangaDetails {
        let slug = mangaSlug(from: mangaIDOrURL)
        guard !slug.isEmpty else { throw RuntimeSourceError.mangaNotFound }
        let html = try await getHTML(try websiteURL("/\(mangaPath)/\(slug)/"), ttl: 60 * 30)

        let title = firstMatch(
            html,
            patterns: [
                #"<(?:h1|h2|h3)[^>]*class=["'][^"']*entry-title[^"']*["'][^>]*>([\s\S]*?)</(?:h1|h2|h3)>"#,
                #"<[^>]+class=["'][^"']*ts-breadcrumb[^"']*["'][^>]*>[\s\S]*<li[^>]*>[\s\S]*?<span[^>]*>([\s\S]*?)</span>"#,
                #"<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']"#,
                #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:title["']"#
            ]
        ).map(SourceEngineUtilities.stripHTML)

        let description = firstMatch(
            html,
            patterns: [
                #"<div[^>]+class=["'][^"']*(?:entry-content[^"']*description|desc)[^"']*["'][^>]*>([\s\S]*?)</div>"#,
                #"<meta[^>]+name=["']description["'][^>]+content=["']([^"']+)["']"#
            ]
        ).map(SourceEngineUtilities.stripHTML) ?? ""

        let cover = firstMatch(
            html,
            patterns: [
                #"<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']"#,
                #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']"#,
                #"<div[^>]+class=["'][^"']*thumb[^"']*["'][^>]*>[\s\S]*?<img[^>]+(?:data-src|src)=["']([^"']+)"#
            ]
        ).map(absoluteURL)

        let author = labelledValue(html, labels: ["Author", "Auteur", "Mangaka", "Pengarang", "Yazar"])
        let status = labelledValue(html, labels: ["Status", "Statut", "Durum", "Estado"])
            .map { statusText($0) } ?? "Unknown"
        let genres = genreNames(from: html)

        return SourceMangaDetails(
            manga: Manga(
                id: mangaID(slug),
                sourceID: source.id,
                title: (title?.isEmpty == false) ? title! : SourceEngineUtilities.titleFromSlug(slug),
                author: (author?.isEmpty == false) ? author! : "Unknown",
                summary: description,
                genres: genres,
                coverHexes: SourceEngineUtilities.palette(for: slug),
                coverURL: cover,
                statusText: status
            )
        )
    }

    func chapters(for manga: Manga) async throws -> SourceChapterDetails {
        let slug = mangaSlug(from: manga.id)
        guard !slug.isEmpty else { throw RuntimeSourceError.mangaNotFound }
        let html = try await getHTML(try websiteURL("/\(mangaPath)/\(slug)/"), ttl: 60 * 20)

        let blocks = SourceEngineUtilities.allMatches(
            in: html,
            pattern: #"(<li\b[^>]*>[\s\S]*?</li>)"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        var seen = Set<String>()
        var output: [Chapter] = []

        for (offset, block) in blocks.enumerated() {
            guard let href = SourceEngineUtilities.firstMatch(
                in: block,
                pattern: #"<a[^>]+href=["']([^"']+)["']"#,
                options: [.caseInsensitive]
            ) else { continue }
            let resolved = absoluteURL(href)
            guard
                looksLikeChapterBlock(block),
                isSameSiteURL(resolved),
                seen.insert(resolved).inserted
            else { continue }

            let nameRaw = firstMatch(
                block,
                patterns: [
                    #"<[^>]+class=["'][^"']*(?:chapternum|lch)[^"']*["'][^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)</a>"#,
                    #"<a[^>]+href=["'][^"']+["'][^>]*>([\s\S]*?)</a>"#
                ]
            )
            let title = nameRaw.map(SourceEngineUtilities.stripHTML).flatMap { $0.isEmpty ? nil : $0 }
                ?? "Chapter \(offset + 1)"
            let dateText = SourceEngineUtilities.firstMatch(
                in: block,
                pattern: #"<[^>]+class=["'][^"']*chapterdate[^"']*["'][^>]*>([\s\S]*?)</[^>]+>"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ).map(SourceEngineUtilities.stripHTML)

            output.append(
                Chapter(
                    id: resolved,
                    mangaID: manga.id,
                    title: title,
                    number: chapterNumber(from: title, fallback: offset),
                    releaseDate: dateText.flatMap(parseDate) ?? .distantPast,
                    isDownloaded: false,
                    pages: []
                )
            )
        }

        guard !output.isEmpty else { throw RuntimeSourceError.invalidResponse }
        return SourceChapterDetails(chapters: output.sorted { $0.number > $1.number })
    }

    func pages(for chapter: Chapter) async throws -> SourcePageAsset {
        guard let chapterURL = URL(string: chapter.id) else { throw RuntimeSourceError.invalidURL }
        let html = try await getHTML(chapterURL, ttl: 60 * 30)
        guard let readerRange = html.range(of: "readerarea", options: [.caseInsensitive]) else {
            throw RuntimeSourceError.chapterPagesMissing
        }
        let readerTail = String(html[readerRange.lowerBound...])
        let imageTags = SourceEngineUtilities.allMatches(
            in: readerTail,
            pattern: #"(<img\b[^>]*>)"#,
            options: [.caseInsensitive]
        )

        var seen = Set<String>()
        let urls = imageTags.compactMap { tag -> String? in
            for attribute in ["data-src", "data-lazy-src", "data-lzl-src", "data-cfsrc", "src"] {
                if let raw = htmlAttribute(attribute, in: tag) {
                    let resolved = absoluteURL(SourceEngineUtilities.decodeHTML(raw).trimmingCharacters(in: .whitespacesAndNewlines))
                    let lowered = resolved.lowercased()
                    guard
                        !lowered.hasPrefix("data:image"),
                        !lowered.contains("logo"),
                        !lowered.contains("avatar"),
                        !lowered.contains("banner"),
                        !lowered.contains("favicon"),
                        seen.insert(resolved).inserted
                    else { return nil }
                    return resolved
                }
            }
            return nil
        }

        guard !urls.isEmpty else { throw RuntimeSourceError.parserEmpty }
        return SourcePageAsset(
            pages: urls.enumerated().map { index, remoteURL in
                ReaderPage(
                    id: "\(chapter.id)#page-\(index + 1)",
                    index: index,
                    title: "Page \(index + 1)",
                    body: "",
                    accentHex: SourceEngineUtilities.paletteColor(seed: "\(chapter.id)-\(index)"),
                    assetKind: .image,
                    assetPath: nil,
                    remoteURL: remoteURL
                )
            },
            errorMessage: nil
        )
    }

    func genreTags() async throws -> [GenreTag] { [] }

    private func list(page: Int, query: String, order: String?) async throws -> [Manga] {
        guard var components = URLComponents(string: "\(baseURL)/\(mangaPath)/") else {
            throw RuntimeSourceError.invalidURL
        }
        var items = [URLQueryItem(name: "page", value: String(max(page, 1)))]
        if !query.isEmpty { items.append(URLQueryItem(name: "title", value: query)) }
        if let order, !order.isEmpty { items.append(URLQueryItem(name: "order", value: order)) }
        components.queryItems = items
        guard let url = components.url else { throw RuntimeSourceError.invalidURL }
        let html = try await getHTML(url, ttl: 60 * 10)

        let anchors = SourceEngineUtilities.allMatchesWithGroups(
            in: html,
            pattern: #"<a\b([^>]*)href=["']([^"']+)["']([^>]*)>([\s\S]*?)</a>"#,
            groupCount: 4
        )
        var seen = Set<String>()
        var mangas: [Manga] = []

        for groups in anchors {
            let attributes = groups[0] + " " + groups[2]
            let href = absoluteURL(groups[1])
            guard let slug = listMangaSlug(from: href), seen.insert(slug).inserted else { continue }
            let title = htmlAttribute("title", in: "<a \(attributes)>")
                .map(SourceEngineUtilities.decodeHTML)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? SourceEngineUtilities.stripHTML(groups[3])
            guard !title.isEmpty else { continue }
            let cover = SourceEngineUtilities.firstMatch(
                in: groups[3],
                pattern: #"<img[^>]+(?:data-src|data-lazy-src|src)=["']([^"']+)"#,
                options: [.caseInsensitive]
            ).map(absoluteURL)

            mangas.append(
                Manga(
                    id: mangaID(slug),
                    sourceID: source.id,
                    title: title,
                    author: "Unknown",
                    summary: "",
                    genres: [],
                    coverHexes: SourceEngineUtilities.palette(for: slug),
                    coverURL: cover,
                    statusText: "Unknown"
                )
            )
        }

        guard !mangas.isEmpty else { throw RuntimeSourceError.parserEmpty }
        return mangas
    }

    private func mangaID(_ slug: String) -> String { "\(source.id)::themesia::\(slug)" }

    private func mangaSlug(from value: String) -> String {
        if let parsed = URL(string: value), parsed.host != nil {
            let parts = parsed.pathComponents.filter { $0 != "/" }
            if let index = parts.firstIndex(of: mangaPath), parts.indices.contains(index + 1) {
                return parts[index + 1]
            }
        }
        let pieces = value.components(separatedBy: "::")
        if let index = pieces.firstIndex(of: "themesia"), pieces.indices.contains(index + 1) {
            return pieces[index + 1]
        }
        return pieces.last ?? value
    }

    private func listMangaSlug(from value: String) -> String? {
        guard let parsed = URL(string: value) else { return nil }
        let parts = parsed.pathComponents.filter { $0 != "/" }
        guard
            let index = parts.firstIndex(of: mangaPath),
            parts.indices.contains(index + 1),
            parts.count == index + 2
        else { return nil }
        let slug = parts[index + 1]
        return slug.isEmpty ? nil : slug
    }

    private func looksLikeChapterBlock(_ block: String) -> Bool {
        let lowered = block.lowercased()
        return ["chapternum", "chapterdate", "chbox", "eph-num", "lch"].contains { lowered.contains($0) }
    }

    private func isSameSiteURL(_ value: String) -> Bool {
        guard
            let targetHost = URL(string: value)?.host?.lowercased(),
            let baseHost = URL(string: baseURL)?.host?.lowercased()
        else { return false }
        return targetHost == baseHost
    }

    private func websiteURL(_ path: String) throws -> URL {
        guard let url = URL(string: baseURL + (path.hasPrefix("/") ? path : "/" + path)) else {
            throw RuntimeSourceError.invalidURL
        }
        return url
    }

    private func getHTML(_ url: URL, ttl: TimeInterval) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("\(baseURL)/", forHTTPHeaderField: "Referer")
        request.setValue(SourceEngineUtilities.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        await rateLimiter.waitTurn()
        return try await SourceEngineUtilities.html(
            session: session,
            request: request,
            cacheKey: SourceEngineUtilities.cacheKey(namespace: "mangathemesia", request: request),
            ttl: ttl
        )
    }

    private func absoluteURL(_ value: String) -> String {
        let decoded = SourceEngineUtilities.decodeHTML(value).trimmingCharacters(in: .whitespacesAndNewlines)
        if URL(string: decoded)?.scheme != nil { return decoded }
        return URL(string: decoded, relativeTo: URL(string: baseURL + "/"))?.absoluteURL.absoluteString ?? decoded
    }

    private func htmlAttribute(_ name: String, in tag: String) -> String? {
        SourceEngineUtilities.firstMatch(
            in: tag,
            pattern: "\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*[\\\"']([^\\\"']+)",
            options: [.caseInsensitive]
        )
    }

    private func firstMatch(_ text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            if let value = SourceEngineUtilities.firstMatch(
                in: text,
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ) { return value }
        }
        return nil
    }

    private func labelledValue(_ html: String, labels: [String]) -> String? {
        for label in labels {
            let escaped = NSRegularExpression.escapedPattern(for: label)
            let patterns = [
                "(?i)<tr[^>]*>[\\s\\S]{0,120}?\(escaped)[\\s\\S]{0,240}?<td[^>]*>([\\s\\S]*?)</td>",
                "(?i)<[^>]+class=[\\\"'][^\\\"']*imptdt[^\\\"']*[\\\"'][^>]*>[\\s\\S]{0,80}?\(escaped)[\\s\\S]{0,160}?<(?:i|a|span)[^>]*>([\\s\\S]*?)</(?:i|a|span)>"
            ]
            if let raw = firstMatch(html, patterns: patterns) {
                let value = SourceEngineUtilities.stripHTML(raw)
                if !value.isEmpty, value != "-", value.lowercased() != "n/a" { return value }
            }
        }
        return nil
    }

    private func genreNames(from html: String) -> [String] {
        let groups = SourceEngineUtilities.allMatchesWithGroups(
            in: html,
            pattern: #"<a[^>]+href=["'][^"']*(?:genre|manga-genre)[^"']*["'][^>]*>([\s\S]*?)</a>"#,
            groupCount: 1
        )
        var seen = Set<String>()
        return groups.compactMap { group in
            guard let raw = group.first else { return nil }
            let value = SourceEngineUtilities.stripHTML(raw)
            return !value.isEmpty && seen.insert(value.lowercased()).inserted ? value : nil
        }
    }

    private func statusText(_ raw: String) -> String {
        let value = raw.lowercased()
        if ["completed", "complete", "finished", "tamat", "完結"].contains(where: value.contains) { return "Completed" }
        if ["hiatus", "on hold", "season end"].contains(where: value.contains) { return "Hiatus" }
        if ["dropped", "cancelled", "canceled", "discontinued"].contains(where: value.contains) { return "Dropped" }
        if ["ongoing", "publishing", "updating", "berjalan", "連載中"].contains(where: value.contains) { return "Ongoing" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
    }

    private func parseDate(_ text: String) -> Date? {
        let formats = [dateFormat, "MMMM d, yyyy", "MMM d, yyyy", "yyyy-MM-dd"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines)) { return date }
        }
        return nil
    }

    private func chapterNumber(from title: String, fallback: Int) -> Double {
        guard let raw = SourceEngineUtilities.firstMatch(in: title, pattern: #"([0-9]+(?:\.[0-9]+)?)"#),
              let number = Double(raw) else {
            return Double(max(1, 10_000 - fallback))
        }
        return number
    }
}
