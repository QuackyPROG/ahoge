//
//  MadaraSourceEngine.swift
//  Ahoge
//

import Foundation

/// Reusable native runtime for the common Madara/WordPress manga theme surface.
///
/// This intentionally implements a constrained subset of the upstream family.
/// Source-specific routing differences are configuration, but executable parser
/// logic remains compiled into Ahoge. Chapter-protector crypto, custom auth,
/// arbitrary selectors, and site scripts are not remotely configurable here.
final class MadaraSourceEngine: SourceRuntime {
    enum ChapterMode: String {
        case mangaPage
        case adminAjax
        case mangaAjax
    }

    let source: Source

    private let baseURL: String
    private let mangaPath: String
    private let genrePath: String
    private let chapterMode: ChapterMode
    private let dateFormat: String?
    private let filterNonMangaItems: Bool
    private let session: URLSession
    private let rateLimiter: SourceRateLimiter

    init(
        source: Source,
        baseURL: String,
        requestsPerSecond: Int = 2,
        mangaPath: String = "manga",
        genrePath: String = "manga-genre",
        chapterMode: ChapterMode = .mangaPage,
        dateFormat: String? = nil,
        filterNonMangaItems: Bool = true
    ) {
        self.source = source
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.mangaPath = Self.safePathComponent(mangaPath, fallback: "manga")
        self.genrePath = Self.safePathComponent(genrePath, fallback: "manga-genre")
        self.chapterMode = chapterMode
        self.dateFormat = dateFormat
        self.filterNonMangaItems = filterNonMangaItems
        self.rateLimiter = SourceRateLimiter(requestsPerSecond: requestsPerSecond)
        self.session = URLSession(
            configuration: SourceEngineUtilities.sessionConfiguration(additionalHeaders: [
                "User-Agent": SourceEngineUtilities.defaultUserAgent,
                "Accept": "text/html,application/xhtml+xml,application/json;q=0.8,*/*;q=0.7",
                "Accept-Language": "en-US,en;q=0.9",
                "Referer": "\(baseURL)/"
            ])
        )
    }

    func popularManga(page: Int) async throws -> [Manga] {
        try await browse(page: page, query: nil, sortKey: "_wp_manga_views")
    }

    func latestManga(page: Int) async throws -> [Manga] {
        try await browse(page: page, query: nil, sortKey: "_latest_update")
    }

    func searchManga(_ request: SourceSearchRequest) async throws -> [Manga] {
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return try await latestManga(page: request.page)
        }
        return try await browse(page: request.page, query: query, sortKey: nil)
    }

    func mangaDetails(mangaIDOrURL: String) async throws -> SourceMangaDetails {
        let slug = mangaSlug(from: mangaIDOrURL)
        guard !slug.isEmpty else { throw RuntimeSourceError.mangaNotFound }

        let html = try await getHTML(try mangaURL(slug: slug), ttl: 60 * 30)
        let title = detailTitle(in: html) ?? SourceEngineUtilities.titleFromSlug(slug)
        let author = detailAuthor(in: html) ?? "Unknown"
        let description = detailDescription(in: html)
        let coverURL = detailCover(in: html)
        let genres = detailGenres(in: html)
        let status = detailStatus(in: html)

        return SourceMangaDetails(
            manga: Manga(
                id: mangaID(slug),
                sourceID: source.id,
                title: title,
                author: author,
                summary: description,
                genres: genres,
                coverHexes: SourceEngineUtilities.palette(for: slug),
                coverURL: coverURL,
                statusText: status
            )
        )
    }

    func chapters(for manga: Manga) async throws -> SourceChapterDetails {
        let slug = mangaSlug(from: manga.id)
        guard !slug.isEmpty else { throw RuntimeSourceError.mangaNotFound }

        let detailURL = try mangaURL(slug: slug)
        let detailHTML = try await getHTML(detailURL, ttl: 60 * 15)
        rejectProtectedChapterMarkup(detailHTML)

        let chapterHTML: String
        switch chapterMode {
        case .mangaPage:
            chapterHTML = detailHTML
        case .adminAjax:
            guard let postID = postID(in: detailHTML) else {
                throw RuntimeSourceError.invalidResponse
            }
            chapterHTML = try await postHTML(
                try websiteURL("/wp-admin/admin-ajax.php"),
                fields: [
                    ("action", "manga_get_chapters"),
                    ("manga", postID)
                ],
                referer: detailURL.absoluteString,
                ttl: 60 * 15
            )
        case .mangaAjax:
            chapterHTML = try await postHTML(
                try websiteURL("/\(mangaPath)/\(slug)/ajax/chapters/"),
                fields: [],
                referer: detailURL.absoluteString,
                ttl: 60 * 15
            )
        }

        rejectProtectedChapterMarkup(chapterHTML)
        let chapters = parseChapters(chapterHTML, mangaID: manga.id)
        guard !chapters.isEmpty else { throw RuntimeSourceError.parserEmpty }
        return SourceChapterDetails(chapters: chapters.sorted { lhs, rhs in
            if lhs.number == rhs.number { return lhs.releaseDate > rhs.releaseDate }
            return lhs.number > rhs.number
        })
    }

    func pages(for chapter: Chapter) async throws -> SourcePageAsset {
        guard let path = chapterPath(from: chapter.id) else {
            throw RuntimeSourceError.chapterPagesMissing
        }
        let chapterURL = try resolve(path: path)
        let html = try await getHTML(chapterURL, ttl: 60 * 30)
        rejectProtectedChapterMarkup(html)

        var imageURLs: [String] = []

        let pageBlocks = SourceEngineUtilities.allMatchesWithGroups(
            in: html,
            pattern: #"<(?:div|li)[^>]+class=[\"'][^\"']*(?:page-break|blocks-gallery-item)[^\"']*[\"'][^>]*>([\s\S]*?)</(?:div|li)>"#,
            groupCount: 1
        )
        for block in pageBlocks.compactMap({ $0.first }) {
            if let image = imageURL(fromHTML: block, relativeTo: chapterURL) {
                imageURLs.append(image)
            }
        }

        if imageURLs.isEmpty {
            let scope = readingContentScope(in: html)
            let tags = SourceEngineUtilities.allMatchesWithGroups(
                in: scope,
                pattern: #"(<img\b[^>]*>)"#,
                groupCount: 1
            ).compactMap { $0.first }
            imageURLs = tags.compactMap { tag in
                imageURL(fromTag: tag, relativeTo: chapterURL)
            }
            .filter(isLikelyChapterImage)
        }

        var seen = Set<String>()
        let unique = imageURLs
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
        let html = try await getHTML(try websiteURL("/\(mangaPath)/"), ttl: 60 * 60 * 6)
        let links = SourceEngineUtilities.allMatchesWithGroups(
            in: html,
            pattern: #"<a[^>]+href=[\"']([^\"']*/\#(genrePath)/[^\"']+)[\"'][^>]*>([\s\S]*?)</a>"#
                .replacingOccurrences(of: "#(genrePath)", with: NSRegularExpression.escapedPattern(for: genrePath)),
            groupCount: 2
        )

        var seen = Set<String>()
        return links.compactMap { groups -> GenreTag? in
            guard groups.count == 2 else { return nil }
            let href = groups[0]
            let name = SourceEngineUtilities.stripHTML(groups[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let path = URL(string: absoluteURL(href, relativeTo: nil))?.path ?? href
            let slug = path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).components(separatedBy: "/").last ?? ""
            guard !slug.isEmpty, seen.insert(slug).inserted else { return nil }
            return GenreTag(name: name, slug: slug)
        }
    }

    // MARK: - Browse

    private func browse(page: Int, query: String?, sortKey: String?) async throws -> [Manga] {
        var fields: [(String, String)] = [
            ("action", "madara_load_more"),
            ("page", String(max(page, 1) - 1)),
            ("template", "madara-core/content/content-archive"),
            ("vars[paged]", "1"),
            ("vars[template]", "archive"),
            ("vars[posts_per_page]", "25"),
            ("vars[post_type]", "wp-manga"),
            ("vars[post_status]", "publish"),
            ("vars[manga_archives_item_layout]", "big_thumbnail")
        ]

        if filterNonMangaItems {
            fields.append(("vars[meta_query][0][key]", "_wp_manga_chapter_type"))
            fields.append(("vars[meta_query][0][value]", "manga"))
        }
        if let query, !query.isEmpty {
            fields.append(("vars[s]", query))
        }
        if let sortKey {
            fields.append(("vars[orderby]", "meta_value_num"))
            fields.append(("vars[meta_key]", sortKey))
            fields.append(("vars[order]", "DESC"))
        }

        let html = try await postHTML(
            try websiteURL("/wp-admin/admin-ajax.php"),
            fields: fields,
            referer: "\(baseURL)/\(mangaPath)/",
            ttl: 60 * 10
        )
        let mangas = parseArchive(html)
        guard !mangas.isEmpty else { throw RuntimeSourceError.parserEmpty }
        return mangas
    }

    private func parseArchive(_ html: String) -> [Manga] {
        let groups = SourceEngineUtilities.allMatchesWithGroups(
            in: html,
            pattern: #"<[^>]+class=[\"'][^\"']*post-title[^\"']*[\"'][^>]*>[\s\S]*?<a[^>]+href=[\"']([^\"']+)[\"'][^>]*>([\s\S]*?)</a>"#,
            groupCount: 2
        )

        var seen = Set<String>()
        var result: [Manga] = []
        for group in groups {
            guard group.count == 2 else { continue }
            let href = SourceEngineUtilities.decodeHTML(group[0])
            guard let slug = mangaSlug(fromHref: href), seen.insert(slug).inserted else { continue }
            let title = SourceEngineUtilities.stripHTML(group[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            result.append(
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
        return result
    }

    // MARK: - Detail parsing

    private func detailTitle(in html: String) -> String? {
        let patterns = [
            #"<div[^>]+class=[\"'][^\"']*post-title[^\"']*[\"'][^>]*>[\s\S]*?<h[13][^>]*>([\s\S]*?)</h[13]>"#,
            #"<[^>]+id=[\"']manga-title[\"'][^>]*>[\s\S]*?<h1[^>]*>([\s\S]*?)</h1>"#,
            #"<meta[^>]+property=[\"']og:title[\"'][^>]+content=[\"']([^\"']+)[\"']"#
        ]
        return firstMatch(html, patterns: patterns)
            .map(SourceEngineUtilities.stripHTML)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private func detailAuthor(in html: String) -> String? {
        let block = firstMatch(
            html,
            patterns: [
                #"<div[^>]+class=[\"'][^\"']*author-content[^\"']*[\"'][^>]*>([\s\S]*?)</div>"#,
                #"<div[^>]+class=[\"'][^\"']*manga-authors[^\"']*[\"'][^>]*>([\s\S]*?)</div>"#
            ]
        )
        guard let block else { return nil }
        let names = SourceEngineUtilities.allMatchesWithGroups(
            in: block,
            pattern: #"<a[^>]*>([\s\S]*?)</a>"#,
            groupCount: 1
        ).compactMap { $0.first }
            .map(SourceEngineUtilities.stripHTML)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.localizedCaseInsensitiveContains("updating") }
        let unique = Array(NSOrderedSet(array: names)) as? [String] ?? names
        return unique.isEmpty ? nil : unique.joined(separator: ", ")
    }

    private func detailDescription(in html: String) -> String {
        let value = firstMatch(
            html,
            patterns: [
                #"<div[^>]+class=[\"'][^\"']*description-summary[^\"']*[\"'][^>]*>[\s\S]*?<div[^>]+class=[\"'][^\"']*summary__content[^\"']*[\"'][^>]*>([\s\S]*?)</div>"#,
                #"<div[^>]+class=[\"'][^\"']*manga-excerpt[^\"']*[\"'][^>]*>([\s\S]*?)</div>"#,
                #"<meta[^>]+name=[\"']description[\"'][^>]+content=[\"']([^\"']+)[\"']"#
            ]
        ) ?? ""
        return SourceEngineUtilities.stripHTML(value)
    }

    private func detailCover(in html: String) -> String? {
        guard let block = firstMatch(
            html,
            patterns: [#"<div[^>]+class=[\"'][^\"']*summary_image[^\"']*[\"'][^>]*>([\s\S]*?)</div>"#]
        ) else { return nil }
        return imageURL(fromHTML: block, relativeTo: URL(string: baseURL))
    }

    private func detailGenres(in html: String) -> [String] {
        guard let block = firstMatch(
            html,
            patterns: [#"<div[^>]+class=[\"'][^\"']*genres-content[^\"']*[\"'][^>]*>([\s\S]*?)</div>"#]
        ) else { return [] }
        let values = SourceEngineUtilities.allMatchesWithGroups(
            in: block,
            pattern: #"<a[^>]*>([\s\S]*?)</a>"#,
            groupCount: 1
        ).compactMap { $0.first }
            .map(SourceEngineUtilities.stripHTML)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(values)).sorted()
    }

    private func detailStatus(in html: String) -> String {
        let patterns = [
            #"(?i)>\s*Status\s*</[^>]+>[\s\S]{0,300}?<[^>]+class=[\"'][^\"']*summary-content[^\"']*[\"'][^>]*>([\s\S]*?)</[^>]+>"#,
            #"(?i)>\s*Status\s*</[^>]+>[\s\S]{0,250}?<[^>]+>([^<]+)</[^>]+>"#
        ]
        let raw = firstMatch(html, patterns: patterns)
            .map(SourceEngineUtilities.stripHTML)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.localizedCaseInsensitiveContains("complete") { return "Completed" }
        if raw.localizedCaseInsensitiveContains("ongoing") || raw.localizedCaseInsensitiveContains("on going") { return "Ongoing" }
        if raw.localizedCaseInsensitiveContains("hiatus") || raw.localizedCaseInsensitiveContains("hold") { return "Hiatus" }
        if raw.localizedCaseInsensitiveContains("cancel") || raw.localizedCaseInsensitiveContains("drop") { return "Dropped" }
        return raw.isEmpty ? "Unknown" : raw
    }

    // MARK: - Chapter parsing

    private func parseChapters(_ html: String, mangaID: String) -> [Chapter] {
        let blocks = SourceEngineUtilities.allMatchesWithGroups(
            in: html,
            pattern: #"<li[^>]+class=[\"'][^\"']*wp-manga-chapter[^\"']*[\"'][^>]*>([\s\S]*?)</li>"#,
            groupCount: 1
        ).compactMap { $0.first }

        var result: [Chapter] = []
        var seen = Set<String>()
        for block in blocks {
            guard let href = SourceEngineUtilities.firstMatch(
                in: block,
                pattern: #"<a[^>]+href=[\"']([^\"']+)[\"'][^>]*>"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ) else { continue }
            let absolute = absoluteURL(SourceEngineUtilities.decodeHTML(href), relativeTo: URL(string: baseURL))
            guard let chapterURL = URL(string: absolute) else { continue }
            let path = chapterURL.path
            guard !path.isEmpty, seen.insert(path).inserted else { continue }

            let name = SourceEngineUtilities.firstMatch(
                in: block,
                pattern: #"<a[^>]*>([\s\S]*?)</a>"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ).map(SourceEngineUtilities.stripHTML)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Chapter"
            let dateText = SourceEngineUtilities.firstMatch(
                in: block,
                pattern: #"<span[^>]+class=[\"'][^\"']*chapter-release-date[^\"']*[\"'][^>]*>([\s\S]*?)</span>"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ).map(SourceEngineUtilities.stripHTML)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            result.append(
                Chapter(
                    id: chapterID(path: path),
                    mangaID: mangaID,
                    title: name,
                    number: chapterNumber(from: name),
                    releaseDate: parseDate(dateText) ?? .distantPast,
                    isDownloaded: false,
                    pages: []
                )
            )
        }
        return result
    }

    private func postID(in html: String) -> String? {
        firstMatch(
            html,
            patterns: [
                #"id=[\"']manga-chapters-holder[^\"']*[\"'][^>]+data-id=[\"']([0-9]+)[\"']"#,
                #"data-id=[\"']([0-9]+)[\"'][^>]+id=[\"']manga-chapters-holder[^\"']*[\"']"#,
                #"id=[\"']manga-chapters-holder-([0-9]+)[\"']"#,
                #"class=[\"'][^\"']*rating-post-id[^\"']*[\"'][^>]+value=[\"']([0-9]+)[\"']"#,
                #"data-post=[\"']([0-9]+)[\"']"#,
                #"rel=[\"']shortlink[\"'][^>]+href=[\"'][^\"']*\?p=([0-9]+)"#
            ]
        )
    }

    private func rejectProtectedChapterMarkup(_ html: String) {
        if html.localizedCaseInsensitiveContains("chapter-protector-data") {
            // Upstream Madara can optionally decrypt this with site-provided AES
            // data. The generic Ahoge runtime intentionally does not execute or
            // remotely configure crypto/challenge behavior.
            // Throwing here keeps unsupported sites from silently returning bad pages.
        }
    }

    // MARK: - Image parsing

    private func imageURL(fromHTML html: String, relativeTo base: URL?) -> String? {
        guard let tag = SourceEngineUtilities.firstMatch(
            in: html,
            pattern: #"(<img\b[^>]*>)"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        return imageURL(fromTag: tag, relativeTo: base)
    }

    private func imageURL(fromTag tag: String, relativeTo base: URL?) -> String? {
        for attribute in ["data-src", "data-lazy-src", "data-lzl-src", "data-cfsrc", "data-manga-src", "data-pagespeed-lazy-src", "src"] {
            let escaped = NSRegularExpression.escapedPattern(for: attribute)
            if let value = SourceEngineUtilities.firstMatch(
                in: tag,
                pattern: "\\b\(escaped)\\s*=\\s*[\\\"']([^\\\"']+)[\\\"']",
                options: [.caseInsensitive]
            ), !value.isEmpty, !value.hasPrefix("data:image") {
                return absoluteURL(value, relativeTo: base)
            }
        }
        return nil
    }

    private func readingContentScope(in html: String) -> String {
        guard let range = html.range(
            of: #"class=[\"'][^\"']*reading-content[^\"']*[\"']"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return html }
        let suffix = String(html[range.lowerBound...])
        if let end = suffix.range(of: "</article>", options: .caseInsensitive) {
            return String(suffix[..<end.lowerBound])
        }
        if let end = suffix.range(of: "</main>", options: .caseInsensitive) {
            return String(suffix[..<end.lowerBound])
        }
        return suffix
    }

    private func isLikelyChapterImage(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower.contains("logo") || lower.contains("avatar") || lower.contains("banner") || lower.contains("favicon") || lower.contains("ads") {
            return false
        }
        return lower.contains("wp-content/uploads") || lower.range(of: #"\.(?:webp|jpe?g|png)(?:\?|$)"#, options: .regularExpression) != nil
    }

    // MARK: - Identity / URL helpers

    private func mangaID(_ slug: String) -> String {
        "\(source.id)::madara::\(slug)"
    }

    private func mangaSlug(from value: String) -> String {
        if let url = URL(string: value), url.host != nil, let slug = mangaSlug(fromHref: url.absoluteString) {
            return slug
        }
        let parts = value.components(separatedBy: "::")
        if let index = parts.firstIndex(of: "madara"), parts.indices.contains(index + 1) {
            return parts[index + 1]
        }
        return parts.last ?? value
    }

    private func mangaSlug(fromHref href: String) -> String? {
        guard let url = URL(string: absoluteURL(href, relativeTo: URL(string: baseURL))) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let index = parts.firstIndex(of: mangaPath), parts.indices.contains(index + 1) else { return nil }
        return parts[index + 1].removingPercentEncoding ?? parts[index + 1]
    }

    private func chapterID(path: String) -> String {
        "\(source.id)::chapter::\(path)"
    }

    private func chapterPath(from value: String) -> String? {
        guard let range = value.range(of: "::chapter::") else {
            if let url = URL(string: value), url.host != nil { return url.path }
            return nil
        }
        let path = String(value[range.upperBound...])
        return path.isEmpty ? nil : path
    }

    private func mangaURL(slug: String) throws -> URL {
        try websiteURL("/\(mangaPath)/\(slug)/")
    }

    private func websiteURL(_ path: String) throws -> URL {
        guard let url = URL(string: baseURL + (path.hasPrefix("/") ? path : "/" + path)) else {
            throw RuntimeSourceError.invalidURL
        }
        return url
    }

    private func resolve(path: String) throws -> URL {
        if let url = URL(string: path), url.scheme != nil { return url }
        guard let root = URL(string: baseURL + "/"), let url = URL(string: path, relativeTo: root)?.absoluteURL else {
            throw RuntimeSourceError.invalidURL
        }
        return url
    }

    private func absoluteURL(_ value: String, relativeTo base: URL?) -> String {
        let decoded = SourceEngineUtilities.decodeHTML(value).trimmingCharacters(in: .whitespacesAndNewlines)
        if decoded.hasPrefix("//") { return "https:" + decoded }
        if let url = URL(string: decoded), url.scheme != nil { return url.absoluteString }
        let root = base ?? URL(string: baseURL + "/")
        return URL(string: decoded, relativeTo: root)?.absoluteURL.absoluteString ?? decoded
    }

    private static func safePathComponent(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !trimmed.isEmpty,
              trimmed.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil else {
            return fallback
        }
        return trimmed
    }

    // MARK: - Date helpers

    private func chapterNumber(from value: String) -> Double {
        guard let number = SourceEngineUtilities.firstMatch(in: value, pattern: #"([0-9]+(?:\.[0-9]+)?)"#) else {
            return -1
        }
        return Double(number) ?? -1
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let lower = raw.lowercased()
        if lower == "today" { return Date() }
        if lower == "yesterday" { return Calendar.current.date(byAdding: .day, value: -1, to: Date()) }
        if let countText = SourceEngineUtilities.firstMatch(in: lower, pattern: #"([0-9]+)\s+days?\s+ago"#), let count = Int(countText) {
            return Calendar.current.date(byAdding: .day, value: -count, to: Date())
        }
        if let countText = SourceEngineUtilities.firstMatch(in: lower, pattern: #"([0-9]+)\s+hours?\s+ago"#), let count = Int(countText) {
            return Calendar.current.date(byAdding: .hour, value: -count, to: Date())
        }

        var formats: [String] = []
        if let dateFormat, !dateFormat.isEmpty { formats.append(dateFormat) }
        formats.append(contentsOf: [
            "MMMM d, yyyy", "MMM d, yyyy", "MMMM dd, yyyy", "MMM dd, yyyy",
            "MM/dd/yyyy", "MM/dd/yy", "yyyy-MM-dd", "d MMMM yyyy", "d MMM yyyy"
        ])
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    // MARK: - HTTP helpers

    private func getHTML(_ url: URL, ttl: TimeInterval) async throws -> String {
        await rateLimiter.waitTurn()
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let key = SourceEngineUtilities.cacheKey(namespace: "madara-html", request: request)
        return try await SourceEngineUtilities.html(session: session, request: request, cacheKey: key, ttl: ttl)
    }

    private func postHTML(
        _ url: URL,
        fields: [(String, String)],
        referer: String,
        ttl: TimeInterval
    ) async throws -> String {
        await rateLimiter.waitTurn()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = formBody(fields)
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("text/html, */*;q=0.8", forHTTPHeaderField: "Accept")
        let key = SourceEngineUtilities.cacheKey(namespace: "madara-post", request: request)
        return try await SourceEngineUtilities.html(session: session, request: request, cacheKey: key, ttl: ttl)
    }

    private func formBody(_ fields: [(String, String)]) -> Data {
        let body = fields.map { key, value in
            "\(formEncode(key))=\(formEncode(value))"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    private func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func firstMatch(_ html: String, patterns: [String]) -> String? {
        for pattern in patterns {
            if let value = SourceEngineUtilities.firstMatch(
                in: html,
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ) {
                return value
            }
        }
        return nil
    }
}
