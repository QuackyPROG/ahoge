import Combine
import Foundation
import GRDB

/// The library database. Each manga is loaded once and kept, so every view and the reader share
/// the same objects; changes go through here, which saves them and tells observing views.
@MainActor
final class LibraryRepository: ObservableObject {
    private let db: any DatabaseWriter
    private var loaded: [String: LibraryManga] = [:]
    /// Keys looked up and not in the database, so a view asking every redraw costs no query.
    private var absent: Set<String> = []

    /// Library titles and their chapters are loaded up front; other manga on first lookup.
    init(db: any DatabaseWriter) throws {
        self.db = db
        try Self.migrator.migrate(db)
        let library = try db.read { db in
            try Self.withChapters(LibraryManga.filter(Column(LibraryManga.CodingKeys.inLibrary) == true).fetchAll(db), db)
        }
        for manga in library { loaded[manga.key] = manga }
    }

    /// The on-device library (Application Support/library.sqlite).
    static func open() throws -> LibraryRepository {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return try open(at: folder.appendingPathComponent("library.sqlite"))
    }

    static func open(at file: URL) throws -> LibraryRepository {
        try LibraryRepository(db: DatabaseQueue(path: file.path))
    }

    /// For tests and previews.
    static func inMemory() throws -> LibraryRepository {
        try LibraryRepository(db: DatabaseQueue())
    }

    private nonisolated static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: LibraryManga.databaseTableName) { t in
                t.primaryKey("key", .text)
                t.column("sourceId", .text).notNull()
                t.column("url", .text).notNull()
                t.column("title", .text).notNull()
                t.column("coverUrl", .text).notNull()
                t.column("author", .text).notNull()
                t.column("artist", .text).notNull()
                t.column("summary", .text).notNull()
                t.column("genres", .text).notNull()
                t.column("status", .text).notNull()
                t.column("inLibrary", .boolean).notNull().indexed()
                t.column("dateAdded", .datetime)
                t.column("lastReadAt", .datetime)
                t.column("lastChapterFetch", .datetime)
            }
            try db.create(table: ChapterRecord.databaseTableName) { t in
                t.primaryKey("key", .text)
                t.column("mangaKey", .text).notNull().indexed().references(LibraryManga.databaseTableName, onDelete: .cascade)
                t.column("url", .text).notNull()
                t.column("name", .text).notNull()
                t.column("number", .double).notNull()
                t.column("dateUpload", .datetime)
                t.column("scanlator", .text)
                t.column("read", .boolean).notNull()
                t.column("lastPageRead", .integer).notNull()
                t.column("sourceOrder", .integer).notNull()
            }
        }
        return migrator
    }

    private nonisolated static func withChapters(_ manga: [LibraryManga], _ db: Database) throws -> [LibraryManga] {
        let byKey = Dictionary(manga.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let chapters = try ChapterRecord.filter(byKey.keys.contains(Column(ChapterRecord.CodingKeys.mangaKey))).fetchAll(db)
        for chapter in chapters {
            guard let owner = byKey[chapter.mangaKey] else { continue }
            chapter.manga = owner
            owner.chapters.append(chapter)
        }
        return manga
    }

    /// Titles saved to the Library.
    var library: [LibraryManga] { loaded.values.filter(\.inLibrary) }

    func manga(sourceId: String, url: String) -> LibraryManga? {
        let key = LibraryManga.makeKey(sourceId: sourceId, url: url)
        if let manga = loaded[key] { return manga }
        guard !absent.contains(key) else { return nil }
        let found = try? db.read { db in
            try LibraryManga.fetchOne(db, key: key).map { try Self.withChapters([$0], db)[0] }
        }
        if let found { loaded[key] = found } else { absent.insert(key) }
        return found
    }

    @discardableResult
    func upsert(sourceId: String, url: String, title: String, cover: String) -> LibraryManga {
        if let existing = manga(sourceId: sourceId, url: url) { return existing }
        let manga = LibraryManga(sourceId: sourceId, url: url, title: title, coverUrl: cover)
        objectWillChange.send()
        loaded[manga.key] = manga
        absent.remove(manga.key)
        write { try manga.insert($0) }
        return manga
    }

    @discardableResult
    func upsert(sourceId: String, url: String, details: MangaDetails) -> LibraryManga {
        let manga = upsert(sourceId: sourceId, url: url, title: details.title, cover: details.cover)
        objectWillChange.send()
        if !details.title.isEmpty { manga.title = details.title }
        if !details.cover.isEmpty { manga.coverUrl = details.cover }
        manga.author = details.author
        manga.artist = details.artist
        manga.summary = details.description
        manga.genres = details.genres
        manga.status = details.status
        write { try manga.update($0) }
        return manga
    }

    func applyChapters(_ fetched: [SourceChapter], to manga: LibraryManga) {
        objectWillChange.send()
        let existing = manga.chapters
        let merged = ChapterMerge.merge(existing: existing.map(\.state), fetched: fetched)
        let byURL = Dictionary(existing.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        let keep = Set(merged.map(\.url))
        let removed = existing.filter { !keep.contains($0.url) }
        manga.chapters = merged.map { state in
            if let record = byURL[state.url] {
                record.objectWillChange.send()
                record.apply(state)
                return record
            }
            return ChapterRecord(manga: manga, state: state)
        }
        manga.lastChapterFetch = Date()
        write { db in
            for record in removed { try record.delete(db) }
            // upsert: a chapter key already stored under another manga moves here, as SwiftData's unique key did.
            for record in manga.chapters { try record.upsert(db) }
            try manga.update(db)
        }
    }

    func setInLibrary(_ manga: LibraryManga, _ value: Bool) {
        objectWillChange.send()
        manga.inLibrary = value
        manga.dateAdded = value ? (manga.dateAdded ?? Date()) : nil
        write { try manga.update($0) }
    }

    func setRead(_ chapters: [ChapterRecord], _ read: Bool) {
        objectWillChange.send()
        for chapter in chapters {
            chapter.objectWillChange.send()
            chapter.read = read
            if !read { chapter.lastPageRead = 0 }
        }
        write { db in
            for chapter in chapters { try chapter.update(db) }
        }
    }

    /// Marks this chapter and every older one (higher sourceOrder) as read.
    func markPreviousRead(_ chapter: ChapterRecord, in manga: LibraryManga) {
        setRead(manga.chapters.filter { $0.sourceOrder >= chapter.sourceOrder }, true)
    }

    func saveProgress(_ chapter: ChapterRecord, page: Int, pageCount: Int) {
        guard chapter.lastPageRead != page || (page >= pageCount - 1 && !chapter.read) else { return }
        objectWillChange.send()
        chapter.objectWillChange.send()
        chapter.lastPageRead = page
        if page >= pageCount - 1 { chapter.read = true }
        let manga = chapter.manga
        manga?.lastReadAt = Date()
        write { db in
            try chapter.update(db)
            try manga?.update(db)
        }
    }

    private func write(_ updates: (Database) throws -> Void) {
        _ = try? db.write(updates)
    }
}
