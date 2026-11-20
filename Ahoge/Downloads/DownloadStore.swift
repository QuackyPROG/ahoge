import Foundation

/// Where downloaded chapters live on disk. Internal to the downloads module: callers go through
/// `DownloadManager`.
///
/// Layout: `root/<sourceId>/<mangaKeyHash>/<chapterKeyHash>/001.jpg`, or `<chapterKeyHash>.cbz`
/// beside that folder once zipped. A `.partial` file marks a folder still being written, so a crash
/// mid-chapter never looks downloaded.
struct DownloadStore: Sendable {
    struct Location: Hashable, Sendable {
        let sourceId: String
        let mangaKey: String
        let chapterKey: String
    }

    let root: URL
    /// Where CBZ chapters are unpacked to be read (the "chapter cache"); safe to empty at any time.
    let cache: URL

    static let partialMarker = ".partial"
    /// The page URLs a partial folder's pages were saved for.
    static let manifest = ".pages"
    /// Test probe: whether the last CBZ unpack ran on the main thread.
    nonisolated(unsafe) static var lastUnpackOnMainThread: Bool?

    /// Keys hold URLs, which are no good as file names; a short hash is.
    static func hash(_ key: String) -> String { String(Data(key.utf8).sha256Hex.prefix(24)) }

    func mangaDirectory(_ location: Location) -> URL {
        root.appendingPathComponent(location.sourceId, isDirectory: true)
            .appendingPathComponent(Self.hash(location.mangaKey), isDirectory: true)
    }

    func chapterDirectory(_ location: Location) -> URL {
        mangaDirectory(location).appendingPathComponent(Self.hash(location.chapterKey), isDirectory: true)
    }

    func archive(_ location: Location) -> URL {
        mangaDirectory(location).appendingPathComponent(Self.hash(location.chapterKey) + ".cbz")
    }

    private func unpacked(_ location: Location) -> URL {
        cache.appendingPathComponent(Self.hash(location.chapterKey), isDirectory: true)
    }

    // MARK: Writing

    /// Creates the chapter folder and marks it partial. Pages already there are kept only when they
    /// were saved for the same page list.
    func begin(_ location: Location, pages: [String]) throws -> URL {
        let directory = chapterDirectory(location)
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = directory.appendingPathComponent(Self.manifest)
        let list = Data(pages.joined(separator: "\n").utf8)
        // A folder from before manifests existed counts as another list.
        if (try? Data(contentsOf: manifest)) != list {
            for name in (try? fm.contentsOfDirectory(atPath: directory.path)) ?? [] where !name.hasPrefix(".") {
                try fm.removeItem(at: directory.appendingPathComponent(name))
            }
            try list.write(to: manifest)
        }
        let marker = directory.appendingPathComponent(Self.partialMarker)
        if !FileManager.default.fileExists(atPath: marker.path) {
            try Data().write(to: marker)
        }
        return directory
    }

    /// Indexes (0-based) of pages already written, so a resumed chapter skips them.
    func existingPages(in directory: URL) -> Set<Int> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names.compactMap { name in
            guard !name.hasPrefix("."), let number = Int(name.prefix { $0 != "." }) else { return nil }
            return number - 1
        })
    }

    /// Writes page `index` as `001.jpg` and so on; the extension follows the image bytes. Fails when
    /// the folder is gone (the chapter was cancelled meanwhile), so nothing is recreated.
    static func writePage(_ data: Data, index: Int, in directory: URL) throws -> Int {
        let file = directory.appendingPathComponent(String(format: "%03d", index + 1) + "." + fileExtension(for: data))
        try data.write(to: file, options: .atomic)
        return data.count
    }

    static func fileExtension(for data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if bytes.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        if bytes.count == 12, Array(bytes[0..<4]) == [0x52, 0x49, 0x46, 0x46], Array(bytes[8..<12]) == [0x57, 0x45, 0x42, 0x50] { return "webp" }
        return "jpg"
    }

    /// Keeps one file per page of a `count`-page list and clears the partial mark, then, when asked,
    /// zips the folder into a .cbz and removes it. Returns the page count and the bytes on disk.
    func finish(_ location: Location, pages count: Int, zip: Bool) throws -> (pages: Int, bytes: Int64) {
        let fm = FileManager.default
        let directory = chapterDirectory(location)
        Self.prune(directory, pages: count)
        try? fm.removeItem(at: directory.appendingPathComponent(Self.manifest))
        try fm.removeItem(at: directory.appendingPathComponent(Self.partialMarker))
        let pageCount = pages(in: directory)?.count ?? 0
        guard zip else { return (pageCount, Self.size(of: directory)) }
        let target = archive(location)
        let temporary = target.appendingPathExtension("tmp")
        try? fm.removeItem(at: temporary)
        // Mapped, not read: the archive is written page by page without holding the chapter in memory.
        let names = try fm.contentsOfDirectory(atPath: directory.path).filter { !$0.hasPrefix(".") }.sorted()
        let files = try names.map { (name: $0, data: try Data(contentsOf: directory.appendingPathComponent($0), options: .alwaysMapped)) }
        try ZipArchive.write(files: files, to: temporary)
        try? fm.removeItem(at: target)
        try fm.moveItem(at: temporary, to: target)
        try fm.removeItem(at: directory)
        return (pageCount, Self.size(of: target))
    }

    /// Moves a chapter's folder or archive to another key's place (its URL changed); the unpacked copy goes.
    func move(_ from: Location, to: Location) {
        let fm = FileManager.default
        try? fm.createDirectory(at: mangaDirectory(to), withIntermediateDirectories: true)
        for (source, target) in [(chapterDirectory(from), chapterDirectory(to)), (archive(from), archive(to))] where fm.fileExists(atPath: source.path) {
            try? fm.removeItem(at: target)
            try? fm.moveItem(at: source, to: target)
        }
        remove(from)
    }

    /// Deletes page files past `count` and, where two share a page number (another image type), the older one.
    private static func prune(_ directory: URL, pages count: Int) {
        let fm = FileManager.default
        var kept: [Int: (file: URL, date: Date)] = [:]
        for name in (try? fm.contentsOfDirectory(atPath: directory.path)) ?? [] where !name.hasPrefix(".") {
            let file = directory.appendingPathComponent(name)
            guard let number = Int(name.prefix { $0 != "." }), number >= 1, number <= count else {
                try? fm.removeItem(at: file)
                continue
            }
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if let other = kept[number] {
                let older = other.date > date ? file : other.file
                try? fm.removeItem(at: older)
                if older == file { continue }
            }
            kept[number] = (file, date)
        }
    }

    /// Removes every trace of a chapter: folder, archive and unpacked copy.
    func remove(_ location: Location) {
        let fm = FileManager.default
        try? fm.removeItem(at: chapterDirectory(location))
        try? fm.removeItem(at: archive(location))
        try? fm.removeItem(at: unpacked(location))
        // Drop the manga folder once it holds nothing.
        let manga = mangaDirectory(location)
        if let left = try? fm.contentsOfDirectory(atPath: manga.path), left.isEmpty {
            try? fm.removeItem(at: manga)
        }
    }

    // MARK: Reading

    /// Page files of a complete folder in page order; nil while partial or empty.
    func pages(in directory: URL) -> [URL]? {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: directory.appendingPathComponent(Self.partialMarker).path),
              let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return nil }
        let pages = names
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { directory.appendingPathComponent($0) }
        return pages.isEmpty ? nil : pages
    }

    /// The chapter's pages: the folder, or the archive unpacked into the chapter cache.
    func localPages(_ location: Location) -> [URL]? {
        if let pages = self.pages(in: chapterDirectory(location)) { return pages }
        let archive = self.archive(location)
        let fm = FileManager.default
        guard fm.fileExists(atPath: archive.path) else { return nil }
        let target = unpacked(location)
        if let pages = self.pages(in: target) { return pages }
        do {
            try? fm.removeItem(at: target)
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            let marker = target.appendingPathComponent(Self.partialMarker)
            try Data().write(to: marker)
            Self.lastUnpackOnMainThread = Thread.isMainThread
            try ZipArchive.extractAll(from: archive, to: target)
            try fm.removeItem(at: marker)
        } catch {
            try? fm.removeItem(at: target)
            return nil
        }
        return pages(in: target)
    }

    /// Page count and size of a finished chapter on disk, or nil when there is none.
    func completed(_ location: Location) -> (pages: Int, bytes: Int64)? {
        let directory = chapterDirectory(location)
        if let pages = self.pages(in: directory) { return (pages.count, Self.size(of: directory)) }
        let archive = self.archive(location)
        guard FileManager.default.fileExists(atPath: archive.path) else { return nil }
        let count: Int
        do {
            count = try ZipArchive.entries(at: archive).filter { !$0.isDirectory }.count
        } catch {
            return nil
        }
        return count > 0 ? (count, Self.size(of: archive)) : nil
    }

    /// "sourceId/mangaHash" for every manga folder on disk, so reindexing checks only those titles.
    func mangaFolders() -> Set<String> {
        let fm = FileManager.default
        var result = Set<String>()
        for source in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] where !source.hasPrefix(".") {
            let folder = root.appendingPathComponent(source, isDirectory: true)
            for manga in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where !manga.hasPrefix(".") {
                result.insert(source + "/" + manga)
            }
        }
        return result
    }

    func mangaFolder(_ location: Location) -> String { location.sourceId + "/" + Self.hash(location.mangaKey) }

    /// The chapter folders and archives (also a `.cbz.tmp` being written) in a manga folder ("sourceId/mangaHash"), with their chapter key hash.
    func chapterEntries(inMangaFolder folder: String) -> [(hash: String, url: URL)] {
        let directory = root.appendingPathComponent(folder, isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.map { name in (String(name.prefix { $0 != "." }), directory.appendingPathComponent(name)) }
    }

    // MARK: Sizes

    func clearCache() { try? FileManager.default.removeItem(at: cache) }

    static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        guard isDirectory.boolValue else {
            return ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
        }
        var total: Int64 = 0
        let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        while let file = enumerator?.nextObject() as? URL {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }
}
