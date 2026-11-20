import Foundation
import GRDB

/// What a migration carries from the old entry to the new one (Mihon's migration options).
struct MigrateOptions: Equatable {
    /// Read state, progress, bookmarks and history, matched by chapter number, and the excluded scanlators.
    var chapters = true
    var categories = true
    var notes = true
    var customCover = true
    /// Deletes the old entry's downloads. `LibraryRepository` doesn't own downloads, so the
    /// caller does this with `DownloadManager.delete` before migrating.
    var deleteDownloads = false
    /// Migrate takes the old entry out of the library; copy (false) keeps both.
    var removeOld = true
}

extension LibraryRepository {
    /// Moves a library entry to another source's copy of it. `new` must already have its chapters
    /// (fetch them first). The new entry joins the library, keeping the old one's date added.
    func migrate(_ old: LibraryManga, to new: LibraryManga, options: MigrateOptions) {
        guard old.key != new.key else { return }
        updatesCache = nil
        objectWillChange.send()
        var changed: [ChapterRecord] = []
        var matched: [(old: String, new: String)] = []
        var excluded: Set<String> = []
        if options.chapters {
            (changed, matched) = carryChapters(from: old, to: new)
            excluded = excludedScanlators(mangaKey: old.key)
        }
        if options.notes, !old.notes.isEmpty { new.notes = old.notes }
        if options.customCover, old.customCover != nil { new.customCover = old.customCover }
        new.inLibrary = true
        new.dateAdded = old.dateAdded ?? new.dateAdded ?? Date()
        if let read = old.lastReadAt, new.lastReadAt.map({ $0 < read }) ?? true { new.lastReadAt = read }
        new.refreshUnreadCount()
        let oldCategories = categoryIds(of: old)
        if options.removeOld {
            old.inLibrary = false
            old.dateAdded = nil
            categoryLinks[old.key] = nil
        }
        write { db in
            for chapter in changed { try chapter.update(db) }
            // The old entry keeps its rows; the new chapters get a copy, keeping the newer date.
            for pair in matched {
                try db.execute(
                    sql: """
                        INSERT INTO history (chapterKey, mangaKey, lastRead, timeRead)
                        SELECT ?, ?, lastRead, timeRead FROM history WHERE chapterKey = ?
                        ON CONFLICT(chapterKey) DO UPDATE SET lastRead = MAX(lastRead, excluded.lastRead), timeRead = MAX(timeRead, excluded.timeRead)
                        """,
                    arguments: [pair.new, new.key, pair.old]
                )
            }
            try new.update(db)
            for scanlator in excluded.sorted() {
                try db.execute(sql: "INSERT OR IGNORE INTO excludedScanlator (mangaKey, scanlator) VALUES (?, ?)", arguments: [new.key, scanlator])
            }
            if options.removeOld {
                try old.update(db)
                try db.execute(sql: "DELETE FROM mangaCategory WHERE mangaKey = ?", arguments: [old.key])
            }
        }
        if options.categories, !oldCategories.isEmpty {
            setCategories(categoryIds(of: new).union(oldCategories), for: new)
        }
        // Mihon copies the reader and chapter flags on every migration, whatever the options.
        PerSeriesReaderSettings.copy(from: old.key, to: new.key, in: preferences)
    }

    /// Mihon's rule: a chapter with an old chapter of the same number takes its read state, bookmark
    /// and, when unread, the furthest page; one without a match is read when an old chapter at or past
    /// its number was read. Returns the chapters that changed and the matched old and new chapter keys.
    private func carryChapters(from old: LibraryManga, to new: LibraryManga) -> (changed: [ChapterRecord], matched: [(old: String, new: String)]) {
        let byNumber = Dictionary(grouping: old.chapters.filter { $0.number >= 0 }, by: \.number)
        let maxRead = old.chapters.filter { $0.read && $0.number >= 0 }.map(\.number).max()
        var changed: [ChapterRecord] = []
        var matched: [(old: String, new: String)] = []
        for chapter in new.chapters where chapter.number >= 0 {
            var read = chapter.read
            var bookmark = chapter.bookmark
            var page = chapter.lastPageRead
            if let matches = byNumber[chapter.number] {
                read = read || matches.contains(where: \.read)
                bookmark = bookmark || matches.contains(where: \.bookmark)
                if !read { page = max(page, matches.map(\.lastPageRead).max() ?? 0) }
                matched += matches.map { (old: $0.key, new: chapter.key) }
            } else if let maxRead, chapter.number <= maxRead {
                read = true
            }
            guard read != chapter.read || bookmark != chapter.bookmark || page != chapter.lastPageRead else { continue }
            chapter.objectWillChange.send()
            chapter.read = read
            chapter.bookmark = bookmark
            chapter.lastPageRead = page
            changed.append(chapter)
        }
        return (changed, matched)
    }
}
