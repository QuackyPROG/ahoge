import Foundation
import GRDB

/// The last chapter read of one manga (a row of Mihon's History).
struct HistoryEntry: Identifiable {
    let manga: LibraryManga
    let chapter: ChapterRecord
    let lastRead: Date
    var id: String { manga.key }

    /// Mihon's resume: this chapter until it is finished, then the next one (nil when none is newer).
    var resumeChapter: ChapterRecord? {
        guard chapter.read else { return chapter }
        return manga.chapters.filter { $0.sourceOrder < chapter.sourceOrder }.max { $0.sourceOrder < $1.sourceOrder }
    }
}

extension LibraryRepository {
    /// Notes that `chapter` is being read, for History and the "Last read" sort.
    func recordHistory(_ chapter: ChapterRecord, at date: Date = Date()) {
        objectWillChange.send()
        let manga = chapter.manga
        manga?.lastReadAt = date
        write { db in
            try Self.upsertHistory(chapter, at: date, db)
            try manga?.update(db)
        }
    }

    nonisolated static func upsertHistory(_ chapter: ChapterRecord, at date: Date, _ db: Database) throws {
        try db.execute(
            sql: "INSERT INTO history (chapterKey, mangaKey, lastRead) VALUES (?, ?, ?) ON CONFLICT(chapterKey) DO UPDATE SET lastRead = excluded.lastRead",
            arguments: [chapter.key, chapter.mangaKey, date]
        )
    }

    /// One entry per manga — its latest chapter — newest first.
    func history() -> [HistoryEntry] {
        let rows = (try? db.read { db in
            // With a single MAX(), SQLite takes the other columns from the row holding the maximum.
            try Row.fetchAll(db, sql: "SELECT chapterKey, mangaKey, MAX(lastRead) AS lastRead FROM history GROUP BY mangaKey ORDER BY lastRead DESC")
        }) ?? []
        return rows.compactMap { row in
            let chapterKey: String = row["chapterKey"]
            guard let manga = manga(key: row["mangaKey"]),
                  let chapter = manga.chapters.first(where: { $0.key == chapterKey }),
                  let lastRead = row["lastRead"] as Date? else { return nil }
            return HistoryEntry(manga: manga, chapter: chapter, lastRead: lastRead)
        }
    }

    func removeHistory(chapterKey: String) {
        objectWillChange.send()
        write { try $0.execute(sql: "DELETE FROM history WHERE chapterKey = ?", arguments: [chapterKey]) }
    }

    func removeHistory(mangaKey: String) {
        objectWillChange.send()
        write { try $0.execute(sql: "DELETE FROM history WHERE mangaKey = ?", arguments: [mangaKey]) }
    }

    func clearHistory() {
        objectWillChange.send()
        write { try $0.execute(sql: "DELETE FROM history") }
    }
}
