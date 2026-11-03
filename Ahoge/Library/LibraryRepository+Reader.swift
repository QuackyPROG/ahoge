import Foundation
import GRDB

extension LibraryRepository {
    /// Bookmarks or unbookmarks chapters (Mihon's chapter bookmark).
    func setBookmark(_ chapters: [ChapterRecord], _ bookmarked: Bool) {
        objectWillChange.send()
        for chapter in chapters {
            chapter.objectWillChange.send()
            chapter.bookmark = bookmarked
        }
        write { db in
            for chapter in chapters { try chapter.update(db) }
        }
    }

    /// Scanlators hidden for a manga; the reader skips their chapters.
    func excludedScanlators(mangaKey: String) -> Set<String> {
        (try? db.read { db in
            try String.fetchSet(db, sql: "SELECT scanlator FROM excludedScanlator WHERE mangaKey = ?", arguments: [mangaKey])
        }) ?? []
    }

    /// Incognito: the global switch, or this source's own. Reading then saves no progress or history.
    func isIncognito(sourceId: String) -> Bool {
        Pref.incognito.value(in: preferences) || Pref.incognitoSources.value(in: preferences).contains(sourceId)
    }
}
