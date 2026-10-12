//
//  WeebCentralSourceEngine.swift
//  Ahoge
//

import Foundation

/// Native common runtime for WeebCentral's public reading surface.
///
/// The adapter intentionally implements only server-rendered public endpoints:
/// search/list, series details, chapter list, chapter image metadata, and the
/// stable tag set. It does not execute remote scripts or import account state.
final class WeebCentralSourceEngine: SourceRuntime {
    let source: Source

    private let baseURL: String
    private let session: URLSession
    private let rateLimiter: SourceRateLimiter

    init(source: Source, baseURL: String, requestsPerSecond: Int = 1) {
        self.source = source
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.rateLimiter = SourceRateLimiter(requestsPerSecond: max(requestsPerSecond, 1))
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
        try await list(page: page, query: "", sort: "Popularity", filters: [])
    }

    func latestManga(page: Int) async throws -> [Manga] {
        try await list(page: page, query: "", sort: "Latest Updates", filters: [])
    }

    func searchManga(_ request: SourceSearchRequest) async throws -> [Manga] {
        let sort = request.filters.compactMap { value -> String? in
            if case let .sort(sort) = value { return sort }
            return nil
        }.last ?? "Best Match"
        return try await list(
            page: max(request.page, 1),
            query: sanitizedSearch(request.query),
            sort: sort,
            filters: request.filters
        )
    }

    func mangaDetails(mangaIDOrURL: String) async throws -> SourceMangaDetails {
        guard let identity = seriesIdentity(from: mangaIDOrURL) else {
            throw RuntimeSourceError.mangaNotFound
        }
        let html = try await getHTML(
            try websiteURL("/series/\(identity.id)/\(identity.slug)"),
            ttl: 60 * 30
        )

        let title = firstNonEmpty([
            firstMatch(html, #"<h1\b[^>]*>([\s\S]*?)</h1>"#),
            metaContent(html, key: "og:title", property: true)
        ]).map(SourceEngineUtilities.stripHTML)
        guard let title, !title.isEmpty else { throw RuntimeSourceError.invalidResponse }

        let description = labelledBlock(html, labels: ["Description"]).flatMap { block in
            firstMatch(block, #"<p\b[^>]*>([\s\S]*?)</p>"#)
        }.map(SourceEngineUtilities.stripHTML)
            ?? metaContent(html, key: "description", property: false).map(SourceEngineUtilities.decodeHTML)
            ?? ""

        let author = labelledLinks(html, labels: ["Author"]).joined(separator: " • ")
        let genres = unique(labelledLinks(html, labels: ["Tag", "Type"]))
        let statusRaw = labelledBlock(html, labels: ["Status"]).flatMap { block in
            firstMatch(block, #"<a\b[^>]*>([\s\S]*?)</a>"#)
        }.map(SourceEngineUtilities.stripHTML)
        let cover = detailCoverURL(from: html)

        return SourceMangaDetails(
            manga: Manga(
                id: mangaID(identity),
                sourceID: source.id,
                title: title,
                author: author.isEmpty ? "Unknown" : author,
                summary: description,
                genres: genres,
                coverHexes: SourceEngineUtilities.palette(for: identity.id),
                coverURL: cover,
                statusText: statusText(statusRaw)
            )
        )
    }

    func chapters(for manga: Manga) async throws -> SourceChapterDetails {
        guard let identity = seriesIdentity(from: manga.id) else {
            throw RuntimeSourceError.mangaNotFound
        }
        let html = try await getHTML(
            try websiteURL("/series/\(identity.id)/full-chapter-list"),
            ttl: 60 * 15
        )

        let anchors = SourceEngineUtilities.allMatchesWithGroups(
            in: html,
            pattern: #"<a\b([^>]*)href=["']([^"']+)["']([^>]*)>([\s\S]*?)</a>"#,
            groupCount: 4
        )
        var output: [Chapter] = []
        var seen = Set<String>()

        for (index, groups) in anchors.enumerated() {
            let body = groups[3]
            guard
                let rawTitle = firstMatch(body, #"<span\b[^>]*class=["'][^"']*flex[^"']*["'][^>]*>[\s\S]*?<span\b[^>]*>([\s\S]*?)</span>"#),
                !SourceEngineUtilities.stripHTML(rawTitle).isEmpty
            else { continue }

            let href = absoluteURL(groups[1])
            guard isSameSiteURL(href), seen.insert(href).inserted else { continue }
            let title = SourceEngineUtilities.stripHTML(rawTitle)
            let dateRaw = firstMatch(body, #"<time\b[^>]*datetime=["']([^"']+)["']"#)
            let fallback = Double(max(anchors.count - index, 1))
            let number = seasonChapter(title) ? fallback : chapterNumber(from: title, fallback: fallback)

            output.append(
                Chapter(
                    id: href,
                    mangaID: manga.id,
                    title: title,
                    number: number,
                    releaseDate: parseISODate(dateRaw) ?? .distantPast,
                    isDownloaded: false,
                    pages: []
                )
            )
        }

        guard !output.isEmpty else { throw RuntimeSourceError.invalidResponse }
        return SourceChapterDetails(chapters: output)
    }

    func pages(for chapter: Chapter) async throws -> SourcePageAsset {
        guard var components = URLComponents(string: chapter.id.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/images") else {
            throw RuntimeSourceError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "is_prev", value: "False"),
            URLQueryItem(name: "reading_style", value: "long_strip")
        ]
        guard let url = components.url else { throw RuntimeSourceError.invalidURL }
        let html = try await getHTML(url, ttl: 60 * 20)

        let readerScope = firstMatch(
            html,
            #"<section\b[^>]*x-data=["'][^"']*scroll[^"']*["'][^>]*>([\s\S]*?)</section>"#
        ) ?? html
        let imageTags = SourceEngineUtilities.allMatches(
            in: readerScope,
            pattern: #"(<img\b[^>]*>)"#,
            options: [.caseInsensitive]
        )

        var seen = Set<String>()
        let urls = imageTags.compactMap { tag -> String? in
            guard let raw = htmlAttribute("src", in: tag) else { return nil }
            let resolved = absoluteURL(raw)
            guard
                URL(string: resolved)?.scheme != nil,
                !resolved.lowercased().hasPrefix("data:image"),
                seen.insert(resolved).inserted
            else { return nil }
            return resolved
        }
        guard !urls.isEmpty else { throw RuntimeSourceError.chapterPagesMissing }

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

    func genreTags() async throws -> [GenreTag] {
        Self.tags.map { GenreTag(name: $0, slug: $0) }
    }

    private func list(
        page: Int,
        query: String,
        sort: String,
        filters: [SourceFilterValue]
    ) async throws -> [Manga] {
        guard var components = URLComponents(string: "\(baseURL)/search/data") else {
            throw RuntimeSourceError.invalidURL
        }
        var items = [
            URLQueryItem(name: "text", value: query),
            URLQueryItem(name: "sort", value: normalizedSort(sort)),
            URLQueryItem(name: "order", value: orderAscending(filters) ? "Ascending" : "Descending"),
            URLQueryItem(name: "official", value: "Any"),
            URLQueryItem(name: "anime", value: "Any"),
            URLQueryItem(name: "adult", value: "Any"),
            URLQueryItem(name: "limit", value: "32"),
            URLQueryItem(name: "offset", value: String((max(page, 1) - 1) * 32)),
            URLQueryItem(name: "display_mode", value: "Full Display")
        ]

        for type in selectedTypes(filters) where !type.isEmpty {
            items.append(URLQueryItem(name: "included_type", value: displayValue(type)))
        }
        for tag in includedTags(filters) where !tag.isEmpty {
            items.append(URLQueryItem(name: "included_tag", value: displayValue(tag)))
        }
        for tag in excludedTags(filters) where !tag.isEmpty {
            items.append(URLQueryItem(name: "excluded_tag", value: displayValue(tag)))
        }
        components.queryItems = items
        guard let url = components.url else { throw RuntimeSourceError.invalidURL }
        let html = try await getHTML(url, ttl: 60 * 10)

        let anchors = SourceEngineUtilities.allMatchesWithGroups(
            in: html,
            pattern: #"<a\b([^>]*)href=["']([^"']*/series/[^"']+)["']([^>]*)>([\s\S]*?)</a>"#,
            groupCount: 4
        )
        var seen = Set<String>()
        var output: [Manga] = []

        for groups in anchors {
            let href = absoluteURL(groups[1])
            guard let identity = seriesIdentity(from: href), seen.insert(identity.id).inserted else { continue }
            let body = groups[3]
            let noClassDivs = SourceEngineUtilities.allMatches(
                in: body,
                pattern: #"<div(?![^>]*\bclass\s*=)[^>]*>([\s\S]*?)</div>"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            )
            let title = noClassDivs.reversed()
                .map(SourceEngineUtilities.stripHTML)
                .first(where: { !$0.isEmpty })
                ?? htmlAttribute("title", in: "<a \(groups[0]) \(groups[2])>")
                    .map(SourceEngineUtilities.decodeHTML)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                ?? SourceEngineUtilities.titleFromSlug(identity.slug)
            guard !title.isEmpty else { continue }

            let cover = sourceImageURL(from: body)
            output.append(
                Manga(
                    id: mangaID(identity),
                    sourceID: source.id,
                    title: title,
                    author: "Unknown",
                    summary: "",
                    genres: [],
                    coverHexes: SourceEngineUtilities.palette(for: identity.id),
                    coverURL: cover,
                    statusText: "Unknown"
                )
            )
        }

        guard !output.isEmpty else { throw RuntimeSourceError.parserEmpty }
        return output
    }

    private func mangaID(_ identity: SeriesIdentity) -> String {
        "\(source.id)::weebcentral::\(identity.id)::\(identity.slug)"
    }

    private func seriesIdentity(from value: String) -> SeriesIdentity? {
        if let url = URL(string: value), url.host != nil {
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count >= 3, parts[0] == "series" else { return nil }
            return SeriesIdentity(id: parts[1], slug: parts[2])
        }

        let pieces = value.components(separatedBy: "::")
        if let index = pieces.firstIndex(of: "weebcentral"),
           pieces.indices.contains(index + 2) {
            return SeriesIdentity(id: pieces[index + 1], slug: pieces[index + 2])
        }
        return nil
    }

    private func labelledBlock(_ html: String, labels: [String]) -> String? {
        for label in labels {
            let escaped = NSRegularExpression.escapedPattern(for: label)
            if let block = firstMatch(
                html,
                #"(<li\b[^>]*>[\s\S]*?<strong\b[^>]*>[^<]*"# + escaped + #"[^<]*</strong>[\s\S]*?</li>)"#
            ) {
                return block
            }
        }
        return nil
    }

    private func labelledLinks(_ html: String, labels: [String]) -> [String] {
        guard let block = labelledBlock(html, labels: labels) else { return [] }
        return SourceEngineUtilities.allMatches(
            in: block,
            pattern: #"<a\b[^>]*>([\s\S]*?)</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        .map(SourceEngineUtilities.stripHTML)
        .filter { !$0.isEmpty }
    }

    private func detailCoverURL(from html: String) -> String? {
        if let og = metaContent(html, key: "og:image", property: true), !og.isEmpty {
            return absoluteURL(og)
        }
        guard let start = html.range(of: "section", options: [.caseInsensitive]) else {
            return sourceImageURL(from: html)
        }
        return sourceImageURL(from: String(html[start.lowerBound...]))
    }

    private func sourceImageURL(from html: String) -> String? {
        if let srcset = firstMatch(html, #"<source\b[^>]*srcset=["']([^"']+)["']"#) {
            let first = srcset.split(separator: ",").first.map(String.init) ?? srcset
            let url = first.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").first.map(String.init) ?? first
            return absoluteURL(url.replacingOccurrences(of: "small", with: "normal"))
        }
        if let src = firstMatch(html, #"<img\b[^>]*src=["']([^"']+)["']"#) {
            return absoluteURL(src)
        }
        return nil
    }

    private func metaContent(_ html: String, key: String, property: Bool) -> String? {
        let attribute = property ? "property" : "name"
        let escaped = NSRegularExpression.escapedPattern(for: key)
        return firstMatch(html, #"<meta\b[^>]*"# + attribute + #"=["']"# + escaped + #"["'][^>]*content=["']([^"']+)["']"#)
            ?? firstMatch(html, #"<meta\b[^>]*content=["']([^"']+)["'][^>]*"# + attribute + #"=["']"# + escaped + #"["']"#)
    }

    private func normalizedSort(_ value: String) -> String {
        let supported = ["Best Match", "Alphabet", "Popularity", "Subscribers", "Recently Added", "Latest Updates"]
        if let exact = supported.first(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
            return exact
        }
        switch value.lowercased() {
        case "popular", "views": return "Popularity"
        case "latest", "updated", "update": return "Latest Updates"
        case "alphabet", "title": return "Alphabet"
        default: return "Best Match"
        }
    }

    private func orderAscending(_ filters: [SourceFilterValue]) -> Bool {
        filters.compactMap { value -> Bool? in
            if case let .orderAscending(flag) = value { return flag }
            return nil
        }.last ?? false
    }

    private func selectedTypes(_ filters: [SourceFilterValue]) -> [String] {
        filters.compactMap { value -> [String]? in
            if case let .types(values) = value { return values }
            return nil
        }.flatMap { $0 }
    }

    private func includedTags(_ filters: [SourceFilterValue]) -> [String] {
        filters.compactMap { value -> [String]? in
            if case let .genreInclude(_, slugs) = value { return slugs }
            return nil
        }.flatMap { $0 }
    }

    private func excludedTags(_ filters: [SourceFilterValue]) -> [String] {
        filters.compactMap { value -> [String]? in
            if case let .genreExclude(_, slugs) = value { return slugs }
            return nil
        }.flatMap { $0 }
    }

    private func displayValue(_ value: String) -> String {
        value.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func sanitizedSearch(_ value: String) -> String {
        value.replacingOccurrences(of: #"[!#:(),-]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func statusText(_ value: String?) -> String {
        switch value?.lowercased() {
        case "ongoing": return "Ongoing"
        case "complete": return "Completed"
        case "hiatus": return "Hiatus"
        case "canceled", "cancelled": return "Cancelled"
        default: return "Unknown"
        }
    }

    private func seasonChapter(_ title: String) -> Bool {
        title.range(of: #"(?:Season|S)\s*\d+"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func chapterNumber(from title: String, fallback: Double) -> Double {
        let patterns = [
            #"(?:chapter|ch\.?|episode|ep\.?)\s*([0-9]+(?:\.[0-9]+)?)"#,
            #"\b([0-9]+(?:\.[0-9]+)?)\b"#
        ]
        for pattern in patterns {
            if let raw = SourceEngineUtilities.firstMatch(
                in: title,
                pattern: pattern,
                options: [.caseInsensitive]
            ), let number = Double(raw) {
                return number
            }
        }
        return fallback
    }

    private func parseISODate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func absoluteURL(_ value: String) -> String {
        let decoded = SourceEngineUtilities.decodeHTML(value).trimmingCharacters(in: .whitespacesAndNewlines)
        if URL(string: decoded)?.scheme != nil { return decoded }
        if decoded.hasPrefix("//") { return "https:" + decoded }
        return baseURL + (decoded.hasPrefix("/") ? decoded : "/" + decoded)
    }

    private func isSameSiteURL(_ value: String) -> Bool {
        guard
            let target = URL(string: value)?.host?.lowercased(),
            let base = URL(string: baseURL)?.host?.lowercased()
        else { return false }
        return target == base
    }

    private func htmlAttribute(_ name: String, in tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return SourceEngineUtilities.firstMatch(
            in: tag,
            pattern: escaped + #"\s*=\s*["']([^"']*)["']"#,
            options: [.caseInsensitive]
        )
    }

    private func firstMatch(_ html: String, _ pattern: String) -> String? {
        SourceEngineUtilities.firstMatch(
            in: html,
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
    }

    private func firstNonEmpty(_ values: [String?]) -> String? {
        values.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }

    private func websiteURL(_ path: String) throws -> URL {
        guard let url = URL(string: baseURL + (path.hasPrefix("/") ? path : "/" + path)) else {
            throw RuntimeSourceError.invalidURL
        }
        return url
    }

    private func getHTML(_ url: URL, ttl: TimeInterval) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(SourceEngineUtilities.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("\(baseURL)/", forHTTPHeaderField: "Referer")
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        await rateLimiter.waitTurn()
        return try await SourceEngineUtilities.html(
            session: session,
            request: request,
            cacheKey: SourceEngineUtilities.cacheKey(namespace: "weebcentral", request: request),
            ttl: ttl
        )
    }

    private struct SeriesIdentity {
        let id: String
        let slug: String
    }

    private static let tags = [
        "Action", "Adult", "Adventure", "Comedy", "Doujinshi", "Drama", "Ecchi", "Fantasy",
        "Gender Bender", "Harem", "Hentai", "Historical", "Horror", "Isekai", "Josei", "Lolicon",
        "Martial Arts", "Mature", "Mecha", "Mystery", "Psychological", "Romance", "School Life",
        "Sci-fi", "Seinen", "Shotacon", "Shoujo", "Shoujo Ai", "Shounen", "Shounen Ai",
        "Slice of Life", "Smut", "Sports", "Supernatural", "Tragedy", "Yaoi", "Yuri", "Other"
    ]
}
