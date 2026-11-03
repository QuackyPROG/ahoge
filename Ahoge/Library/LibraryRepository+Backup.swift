import Foundation
import GRDB

/// What backup and restore need from the database. Restore only adds and merges; it never deletes.
extension LibraryRepository {
    /// Library titles plus any other title with a read or bookmarked chapter or a history entry.
    func mangaForBackup() -> [LibraryManga] {
        let keys = (try? db.read { db in
            try String.fetchAll(db, sql: """
                SELECT key FROM manga WHERE inLibrary = 1
                OR key IN (SELECT mangaKey FROM chapter WHERE read = 1 OR bookmark = 1)
                OR key IN (SELECT mangaKey FROM history)
                ORDER BY key
                """)
        }) ?? []
        return keys.compactMap { manga(key: $0) }
    }

    /// Excluded scanlator names by manga key.
    func excludedScanlatorsByManga() -> [String: [String]] {
        let rows = (try? db.read { try Row.fetchAll($0, sql: "SELECT mangaKey, scanlator FROM excludedScanlator ORDER BY scanlator") }) ?? []
        var result: [String: [String]] = [:]
        for row in rows {
            let key: String = row["mangaKey"]
            let scanlator: String = row["scanlator"]
            result[key, default: []].append(scanlator)
        }
        return result
    }

    /// History per chapter key: when it was last read and for how long.
    func historyByChapter() -> [String: (lastRead: Date, timeRead: Int)] {
        let rows = (try? db.read { try Row.fetchAll($0, sql: "SELECT chapterKey, lastRead, timeRead FROM history") }) ?? []
        var result: [String: (lastRead: Date, timeRead: Int)] = [:]
        for row in rows {
            guard let date = row["lastRead"] as Date? else { continue }
            let key: String = row["chapterKey"]
            let seconds: Int = row["timeRead"]
            result[key] = (date, seconds)
        }
        return result
    }

    /// The id of the category with this name (any case). A missing one is created with `template`'s settings.
    @discardableResult
    func categoryId(named name: String, creating template: BackupCategory? = nil) -> Int64? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = categories.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) { return existing.id }
        guard let created = createCategory(named: trimmed), let index = categories.firstIndex(where: { $0.id == created.id }) else { return nil }
        if let template {
            categories[index].flags = template.flags
            categories[index].sortMode = template.sortMode
            let category = categories[index]
            write { try category.update($0) }
        }
        return created.id
    }

    /// Merges one backed-up title into the database: a chapter is read if it is read on either side,
    /// `lastPageRead` takes the larger value, history keeps the newer date, categories are matched by
    /// name and added to the ones the title already has.
    func restoreManga(_ item: BackupManga) {
        objectWillChange.send()
        updatesCache = nil
        let isNew = self.manga(sourceId: item.sourceId, url: item.url) == nil
        let manga = upsert(sourceId: item.sourceId, url: item.url, title: item.title, cover: item.cover)
        if isNew {
            manga.author = item.author
            manga.artist = item.artist
            manga.summary = item.summary
            manga.genres = item.genres
            manga.status = item.status
        }
        if manga.notes.isEmpty { manga.notes = item.notes }
        if manga.updateInterval == nil { manga.updateInterval = item.updateInterval }
        if manga.customCover == nil, let encoded = item.customCoverData, let data = Data(base64Encoded: encoded) {
            setCustomCover(data, for: manga)
        }
        if item.inLibrary && !manga.inLibrary {
            setInLibrary(manga, true)
            if let added = item.dateAdded { manga.dateAdded = added }
        }

        var local = Dictionary(manga.chapters.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        var changed: [ChapterRecord] = []
        for source in item.chapters {
            if let record = local[source.url] {
                let read = record.read || source.read
                let page = max(record.lastPageRead, source.lastPageRead)
                let bookmark = record.bookmark || source.bookmark
                guard read != record.read || page != record.lastPageRead || bookmark != record.bookmark else { continue }
                record.objectWillChange.send()
                record.read = read
                record.lastPageRead = page
                record.bookmark = bookmark
                changed.append(record)
            } else {
                let state = ChapterState(
                    url: source.url, name: source.name, number: source.number, date: source.dateUpload, scanlator: source.scanlator,
                    read: source.read, lastPageRead: source.lastPageRead, sourceOrder: source.sourceOrder
                )
                let record = ChapterRecord(manga: manga, state: state)
                record.bookmark = source.bookmark
                manga.chapters.append(record)
                local[source.url] = record
                changed.append(record)
            }
        }
        manga.refreshUnreadCount()
        if let newest = item.chapters.compactMap(\.lastRead).max(), newest > (manga.lastReadAt ?? .distantPast) {
            manga.lastReadAt = newest
        }

        write { db in
            for record in changed { try record.upsert(db) }
            for source in item.chapters {
                guard let lastRead = source.lastRead else { continue }
                try db.execute(
                    sql: """
                        INSERT INTO history (chapterKey, mangaKey, lastRead, timeRead) VALUES (?, ?, ?, ?)
                        ON CONFLICT(chapterKey) DO UPDATE SET lastRead = MAX(lastRead, excluded.lastRead), timeRead = MAX(timeRead, excluded.timeRead)
                        """,
                    arguments: [LibraryManga.makeKey(sourceId: manga.sourceId, url: source.url), manga.key, lastRead, source.timeRead]
                )
            }
            for scanlator in item.excludedScanlators {
                try db.execute(sql: "INSERT OR IGNORE INTO excludedScanlator (mangaKey, scanlator) VALUES (?, ?)", arguments: [manga.key, scanlator])
            }
            try manga.update(db)
        }

        if manga.inLibrary {
            let current = categoryIds(of: manga)
            var ids = current
            for name in item.categories {
                if let category = categories.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { ids.insert(category.id) }
            }
            if ids != current { setCategories(ids, for: manga) }
        }
    }
}
