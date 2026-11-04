import Foundation
import GRDB

/// Entry-screen edits: scanlator filter and notes.
extension LibraryRepository {
    /// Replaces the scanlators hidden for a manga. The Updates feed and the reader's next/previous honour them.
    func setExcludedScanlators(_ scanlators: Set<String>, for manga: LibraryManga) {
        updatesCache = nil
        objectWillChange.send()
        write { db in
            try db.execute(sql: "DELETE FROM excludedScanlator WHERE mangaKey = ?", arguments: [manga.key])
            for scanlator in scanlators.sorted() {
                try db.execute(sql: "INSERT INTO excludedScanlator (mangaKey, scanlator) VALUES (?, ?)", arguments: [manga.key, scanlator])
            }
        }
    }

    func setNotes(_ notes: String, for manga: LibraryManga) {
        objectWillChange.send()
        manga.notes = notes
        write { try manga.update($0) }
    }
}
