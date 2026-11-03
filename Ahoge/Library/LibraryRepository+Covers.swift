import Foundation
import GRDB

/// Custom covers (Application Support/covers; the database keeps the file name).
extension LibraryRepository {
    /// Uses `data` (any image) as the cover. False when it is not an image or cannot be saved.
    @discardableResult
    func setCustomCover(_ data: Data, for manga: LibraryManga) -> Bool {
        guard let name = CoverStore.save(data) else { return false }
        setCoverFile(name, for: manga)
        return true
    }

    /// Back to the source's cover.
    func resetCover(of manga: LibraryManga) { setCoverFile(nil, for: manga) }

    private func setCoverFile(_ name: String?, for manga: LibraryManga) {
        objectWillChange.send()
        let old = manga.customCover
        manga.customCover = name
        write { try manga.update($0) }
        // Equal pictures share one file, so keep it while another title still uses it.
        if let old, old != name {
            let shared = (try? db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM manga WHERE customCover = ?", arguments: [old]) }) ?? 0
            if shared == 0 { CoverStore.delete(old) }
        }
    }
}

extension LibraryManga {
    /// What views draw: the custom cover's file URL when there is one, else the source's cover.
    var displayCover: String {
        if let name = customCover, CoverStore.exists(name) { return CoverStore.url(for: name).absoluteString }
        return coverUrl
    }
}
