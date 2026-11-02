import Foundation

/// A chapter a library refresh found (a row of Mihon's Updates).
struct UpdateEntry: Identifiable {
    let manga: LibraryManga
    let chapter: ChapterRecord
    let date: Date
    var id: String { chapter.key }
}

extension LibraryRepository {
    /// Library chapters first seen after their manga was added and after `cutoff`, newest first.
    func updates(since cutoff: Date) -> [UpdateEntry] {
        library.flatMap { manga -> [UpdateEntry] in
            guard let added = manga.dateAdded else { return [] }
            return manga.chapters.compactMap { chapter in
                guard let fetched = chapter.dateFetch, fetched > added, fetched > cutoff else { return nil }
                return UpdateEntry(manga: manga, chapter: chapter, date: fetched)
            }
        }
        // Newest refresh first; within one refresh, the source's order (newest chapter first).
        .sorted { ($0.date, $1.chapter.sourceOrder) > ($1.date, $0.chapter.sourceOrder) }
    }
}
