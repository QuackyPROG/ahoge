import Foundation
import ZIPFoundation

/// Reads manga from a folder on this device: `<root>/<Series>/<Chapter>.cbz|.zip|folder`, plus an optional
/// `cover.jpg` and Mihon's `details.json` in the series folder. A series' `url` is its folder name and a
/// chapter's is `<Series>/<Chapter file or folder name>`. Archives are unpacked lazily into the cache.
final class LocalSource: MangaSource {
    static let id = LibraryBadges.localSourceId

    /// Shown in Sources and used wherever an installed source's name is read. The empty base URL
    /// marks it as having no website (no web view, no share link).
    static let info = InstalledSource(id: id, repoURL: "", name: "Local", lang: "", version: "1", nsfw: false, baseUrl: "", iconURL: nil, sha256: "")

    static let archiveExtensions: Set<String> = ["cbz", "zip"]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "avif", "bmp"]

    let root: URL
    private let cache: URL
    private let files = FileManager.default

    init(root: URL? = nil, cache: URL? = nil) {
        let fm = FileManager.default
        self.root = root ?? (fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory).appendingPathComponent("Local", isDirectory: true)
        self.cache = cache ?? (fm.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory).appendingPathComponent("LocalPages", isDirectory: true)
        try? fm.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    var hasPreferences: Bool { false }

    // MARK: Browsing

    func popular(page: Int) async throws -> MangaListPage { listing(matching: "", newestFirst: false) }
    func latest(page: Int) async throws -> MangaListPage { listing(matching: "", newestFirst: true) }
    func search(query: String, page: Int) async throws -> MangaListPage { listing(matching: query, newestFirst: false) }
    /// The folder has nothing to filter by.
    func search(query: String, page: Int, filters: FilterState) async throws -> MangaListPage { listing(matching: query, newestFirst: false) }
    func filters() async throws -> [SourceFilter] { [] }
    func preferences() async throws -> [SourcePreference] { [] }

    /// Everything fits one page: a folder of series is small.
    private func listing(matching query: String, newestFirst: Bool) -> MangaListPage {
        var folders = seriesFolders()
        if newestFirst {
            folders.sort { modified($0) > modified($1) }
        }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let stubs: [MangaStub] = folders.compactMap { folder in
            let name = folder.lastPathComponent
            let title = readDetails(in: folder)?.title.nonEmpty ?? name
            if !needle.isEmpty,
               title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) == nil,
               name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) == nil { return nil }
            return MangaStub(url: name, title: title, cover: coverURL(in: folder)?.absoluteString ?? "")
        }
        return MangaListPage(manga: stubs, hasNextPage: false)
    }

    func details(url: String) async throws -> MangaDetails {
        let folder = try seriesFolder(url)
        let parsed = readDetails(in: folder)
        var cover = coverURL(in: folder)?.absoluteString ?? ""
        if cover.isEmpty, let first = firstChapterImage(in: folder) { cover = first.absoluteString }
        let object: [String: Any] = [
            "title": parsed?.title.nonEmpty ?? url,
            "cover": cover,
            "author": parsed?.author ?? "",
            "artist": parsed?.artist ?? "",
            "description": parsed?.description ?? "",
            "genres": parsed?.genres ?? [],
            "status": parsed?.status ?? "unknown",
        ]
        return try JSONDecoder().decode(MangaDetails.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func chapters(url: String) async throws -> [SourceChapter] {
        let folder = try seriesFolder(url)
        return chapterEntries(in: folder).map { entry in
            let name = Self.chapterTitle(forFile: entry.lastPathComponent)
            return SourceChapter(
                url: "\(url)/\(entry.lastPathComponent)",
                name: name,
                number: Self.chapterNumber(from: name),
                date: modified(entry).timeIntervalSince1970 * 1000,
                scanlator: nil
            )
        }
    }

    /// Image files of the chapter in reading order, as file URLs. An archive is unpacked once into the cache.
    func pages(url: String) async throws -> [SourcePage] {
        let entry = try chapterEntry(url)
        let directory = Self.isArchive(entry) ? try unpack(entry) : entry
        return imageFiles(in: directory).map { SourcePage(url: $0.absoluteString, headers: [:]) }
    }

    // MARK: Naming

    /// "Chapter 10.cbz" is "Chapter 10": the extension of an archive is not part of the name.
    static func chapterTitle(forFile name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        return archiveExtensions.contains(ext) ? (name as NSString).deletingPathExtension : name
    }

    /// The number after "ch"/"chapter"/"ep" if there is one, else the last number in the name, else -1 (unknown).
    static func chapterNumber(from name: String) -> Double {
        let tagged = try? NSRegularExpression(pattern: #"(?:ch(?:apter)?|ep(?:isode)?)\.?\s*(\d+(?:\.\d+)?)"#, options: .caseInsensitive)
        let any = try? NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#)
        let range = NSRange(name.startIndex..., in: name)
        if let match = tagged?.matches(in: name, range: range).last, let r = Range(match.range(at: 1), in: name) {
            return Double(name[r]) ?? -1
        }
        if let match = any?.matches(in: name, range: range).last, let r = Range(match.range, in: name) {
            return Double(name[r]) ?? -1
        }
        return -1
    }

    // MARK: Files

    private func seriesFolders() -> [URL] {
        children(of: root)
            .filter { isDirectory($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func children(of folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        let all = (try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return all.filter { $0.lastPathComponent != "__MACOSX" }
    }

    /// Archives and subfolders of a series, in natural order ("2" before "10").
    private func chapterEntries(in series: URL) -> [URL] {
        children(of: series)
            .filter { isDirectory($0) || Self.isArchive($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func imageFiles(in directory: URL) -> [URL] {
        guard let walker = files.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var found: [URL] = []
        for case let item as URL in walker where Self.imageExtensions.contains(item.pathExtension.lowercased()) && !item.path.contains("__MACOSX") {
            found.append(item)
        }
        // Natural order of the path below the chapter, so "1/2.jpg" sorts before "1/10.jpg".
        let base = directory.standardizedFileURL.path
        return found.sorted { relative($0, base).localizedStandardCompare(relative($1, base)) == .orderedAscending }
    }

    private func relative(_ url: URL, _ base: String) -> String {
        let path = url.standardizedFileURL.path
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
    }

    private func coverURL(in series: URL) -> URL? {
        children(of: series).first {
            $0.deletingPathExtension().lastPathComponent.lowercased() == "cover" && Self.imageExtensions.contains($0.pathExtension.lowercased())
        }
    }

    /// The first page of the first chapter when it is already a folder; an archive would need unpacking just to list.
    private func firstChapterImage(in series: URL) -> URL? {
        guard let first = chapterEntries(in: series).first, isDirectory(first) else { return nil }
        return imageFiles(in: first).first
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func isArchive(_ url: URL) -> Bool { archiveExtensions.contains(url.pathExtension.lowercased()) }

    /// A source `url` is untrusted input (a deep link, a backup): it must stay inside the folder.
    private func seriesFolder(_ name: String) throws -> URL {
        guard !name.isEmpty, !name.contains("/"), name != "..", name != "." else { throw SourceError.script("Unknown local title") }
        let folder = root.appendingPathComponent(name, isDirectory: true)
        guard isDirectory(folder) else { throw SourceError.script("Local folder \"\(name)\" was not found") }
        return folder
    }

    private func chapterEntry(_ url: String) throws -> URL {
        let parts = url.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty, parts[1] != "..", parts[1] != "." else { throw SourceError.script("Unknown local chapter") }
        let entry = try seriesFolder(parts[0]).appendingPathComponent(parts[1])
        guard files.fileExists(atPath: entry.path) else { throw SourceError.script("Local chapter \"\(parts[1])\" was not found") }
        return entry
    }

    /// Unpacks into `<cache>/<hash of path>-<modified time>/` once; a changed archive gets a new folder.
    private func unpack(_ archive: URL) throws -> URL {
        let stamp = Int(modified(archive).timeIntervalSince1970)
        let name = "\(Self.stableHash(archive.standardizedFileURL.path))-\(stamp)"
        let target = cache.appendingPathComponent(name, isDirectory: true)
        let marker = target.appendingPathComponent(".done")
        if files.fileExists(atPath: marker.path) { return target }
        try? files.removeItem(at: target)
        try files.createDirectory(at: target, withIntermediateDirectories: true)
        try files.unzipItem(at: archive, to: target)
        files.createFile(atPath: marker.path, contents: Data())
        return target
    }

    /// The same on every launch, unlike `hashValue`.
    private static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in text.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return hash
    }

    // MARK: details.json

    private struct Details {
        var title = "", author = "", artist = "", description = "", status = "unknown"
        var genres: [String] = []
    }

    /// Mihon's format: title, author, artist, description, genre (list), status (number or word).
    private func readDetails(in series: URL) -> Details? {
        guard let data = try? Data(contentsOf: series.appendingPathComponent("details.json")),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func string(_ key: String) -> String { (object[key] as? String) ?? "" }
        var details = Details()
        details.title = string("title")
        details.author = string("author")
        details.artist = string("artist")
        details.description = string("description")
        if let genres = object["genre"] as? [String] {
            details.genres = genres
        } else if let genres = object["genre"] as? String {
            details.genres = genres.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        details.status = Self.status(object["status"])
        return details
    }

    /// Mihon's numeric status codes (1 ongoing, 2 completed, 4 publishing finished, 5 cancelled, 6 on hiatus) or a word.
    static func status(_ value: Any?) -> String {
        let text = (value as? String)?.lowercased() ?? (value as? NSNumber).map { "\($0.intValue)" } ?? ""
        switch text {
        case "1", "ongoing": return "ongoing"
        case "2", "4", "completed": return "completed"
        case "5", "cancelled": return "cancelled"
        case "6", "hiatus", "on hiatus": return "hiatus"
        default: return "unknown"
        }
    }

    // MARK: Import

    /// Copies chosen files or folders into the local folder. A loose archive becomes its own series,
    /// named after the file, so it shows up as one title with one chapter.
    func importItems(_ urls: [URL]) throws {
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if isDirectory(url) {
                try copy(url, to: root.appendingPathComponent(url.lastPathComponent, isDirectory: true))
            } else if Self.isArchive(url) {
                let series = root.appendingPathComponent(Self.chapterTitle(forFile: url.lastPathComponent), isDirectory: true)
                try files.createDirectory(at: series, withIntermediateDirectories: true)
                try copy(url, to: series.appendingPathComponent(url.lastPathComponent))
            }
        }
    }

    private func copy(_ source: URL, to destination: URL) throws {
        if files.fileExists(atPath: destination.path) { try files.removeItem(at: destination) }
        try files.copyItem(at: source, to: destination)
    }
}
