import Foundation
import SwiftData

@MainActor
struct LibraryRepository {
    let context: ModelContext

    func manga(sourceId: String, url: String) -> LibraryManga? {
        let key = LibraryManga.makeKey(sourceId: sourceId, url: url)
        var descriptor = FetchDescriptor<LibraryManga>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @discardableResult
    func upsert(sourceId: String, url: String, title: String, cover: String) -> LibraryManga {
        if let existing = manga(sourceId: sourceId, url: url) { return existing }
        let manga = LibraryManga(sourceId: sourceId, url: url, title: title, coverUrl: cover)
        context.insert(manga)
        save()
        return manga
    }

    @discardableResult
    func upsert(sourceId: String, url: String, details: MangaDetails) -> LibraryManga {
        let manga = upsert(sourceId: sourceId, url: url, title: details.title, cover: details.cover)
        if !details.title.isEmpty { manga.title = details.title }
        if !details.cover.isEmpty { manga.coverUrl = details.cover }
        manga.author = details.author
        manga.artist = details.artist
        manga.summary = details.description
        manga.genres = details.genres
        manga.status = details.status
        save()
        return manga
    }

    func applyChapters(_ fetched: [SourceChapter], to manga: LibraryManga) {
        let existing = manga.chapters
        let merged = ChapterMerge.merge(existing: existing.map(\.state), fetched: fetched)
        let byURL = Dictionary(existing.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        let keep = Set(merged.map(\.url))
        for record in existing where !keep.contains(record.url) { context.delete(record) }
        for state in merged {
            if let record = byURL[state.url] {
                record.apply(state)
            } else {
                let record = ChapterRecord(sourceId: manga.sourceId, state: state)
                context.insert(record)
                record.manga = manga
            }
        }
        manga.lastChapterFetch = Date()
        save()
    }

    func setInLibrary(_ manga: LibraryManga, _ value: Bool) {
        manga.inLibrary = value
        manga.dateAdded = value ? (manga.dateAdded ?? Date()) : nil
        save()
    }

    func setRead(_ chapters: [ChapterRecord], _ read: Bool) {
        for chapter in chapters {
            chapter.read = read
            if !read { chapter.lastPageRead = 0 }
        }
        save()
    }

    /// Marks this chapter and every older one (higher sourceOrder) as read.
    func markPreviousRead(_ chapter: ChapterRecord, in manga: LibraryManga) {
        setRead(manga.chapters.filter { $0.sourceOrder >= chapter.sourceOrder }, true)
    }

    func saveProgress(_ chapter: ChapterRecord, page: Int, pageCount: Int) {
        guard chapter.lastPageRead != page || (page >= pageCount - 1 && !chapter.read) else { return }
        chapter.lastPageRead = page
        if page >= pageCount - 1 { chapter.read = true }
        chapter.manga?.lastReadAt = Date()
        save()
    }

    func save() {
        try? context.save()
    }
}
