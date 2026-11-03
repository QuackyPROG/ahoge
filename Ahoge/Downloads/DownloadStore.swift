import Foundation
import ZIPFoundation

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

    /// Creates the chapter folder (keeping pages already there) and marks it partial.
    func begin(_ location: Location) throws -> URL {
        let directory = chapterDirectory(location)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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

    /// Clears the partial mark and, when asked, zips the folder into a .cbz and removes it.
    /// Returns the page count and the bytes on disk.
    func finish(_ location: Location, zip: Bool) throws -> (pages: Int, bytes: Int64) {
        let fm = FileManager.default
        let directory = chapterDirectory(location)
        try fm.removeItem(at: directory.appendingPathComponent(Self.partialMarker))
        let pageCount = pages(in: directory)?.count ?? 0
        guard zip else { return (pageCount, Self.size(of: directory)) }
        let target = archive(location)
        let temporary = target.appendingPathExtension("tmp")
        try? fm.removeItem(at: temporary)
        // Pages are already compressed images; storing them keeps zipping fast.
        try fm.zipItem(at: directory, to: temporary, shouldKeepParent: false, compressionMethod: .none)
        try? fm.removeItem(at: target)
        try fm.moveItem(at: temporary, to: target)
        try fm.removeItem(at: directory)
        return (pageCount, Self.size(of: target))
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
        if let pages = pages(in: chapterDirectory(location)) { return pages }
        let archive = archive(location)
        let fm = FileManager.default
        guard fm.fileExists(atPath: archive.path) else { return nil }
        let target = unpacked(location)
        if let pages = pages(in: target) { return pages }
        do {
            try? fm.removeItem(at: target)
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            let marker = target.appendingPathComponent(Self.partialMarker)
            try Data().write(to: marker)
            try fm.unzipItem(at: archive, to: target)
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
        if let pages = pages(in: directory) { return (pages.count, Self.size(of: directory)) }
        let archive = archive(location)
        guard FileManager.default.fileExists(atPath: archive.path) else { return nil }
        let count: Int
        do {
            let zip: Archive = try Archive(url: archive, accessMode: .read)
            count = zip.reduce(0) { $1.type == .file ? $0 + 1 : $0 }
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
