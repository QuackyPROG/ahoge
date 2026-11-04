import UIKit

/// Custom covers on disk (Application Support/covers). The database keeps only the file name, so
/// the app container moving between installs and updates never breaks the link.
enum CoverStore {
    static var folder: URL {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("covers", isDirectory: true)
    }

    static func url(for name: String) -> URL { folder.appendingPathComponent(name) }

    static func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: url(for: name).path) }

    /// Saves image data as a JPEG named after its hash, so a changed cover is a new file (and a new
    /// image cache key) and the same picture twice is one file. A JPEG keeps its bytes: encoding it
    /// again would lose quality and change the hash, so a restored backup would get a different file.
    /// Returns the file name.
    static func save(_ data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        guard let jpeg = data.starts(with: [0xFF, 0xD8, 0xFF]) ? data : image.jpegData(compressionQuality: 0.9) else { return nil }
        let name = String(jpeg.sha256Hex.prefix(24)) + ".jpg"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try jpeg.write(to: url(for: name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func data(for name: String) -> Data? { try? Data(contentsOf: url(for: name)) }

    static func delete(_ name: String) { try? FileManager.default.removeItem(at: url(for: name)) }
}
