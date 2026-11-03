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
    /// Chapters of scanlators excluded for their manga are left out. The full feed is cached; applyChapters, setInLibrary and setExcludedScanlators clear it.
    func updates(since cutoff: Date) -> [UpdateEntry] {
        let all: [UpdateEntry]
        if let cached = updatesCache {
            all = cached
        } else {
            let excluded = excludedScanlatorsByManga()
            all = library.flatMap { manga -> [UpdateEntry] in
                guard let added = manga.dateAdded else { return [] }
                let hidden = Set(excluded[manga.key] ?? [])
                return manga.chapters.compactMap { chapter in
                    guard let fetched = chapter.dateFetch, fetched > added else { return nil }
                    if let scanlator = chapter.scanlator, hidden.contains(scanlator) { return nil }
                    return UpdateEntry(manga: manga, chapter: chapter, date: fetched)
                }
            }
            // Newest refresh first; within one refresh, by manga, then the source's order (newest chapter first).
            .sorted { ($0.date, $1.manga.key, $1.chapter.sourceOrder) > ($1.date, $0.manga.key, $0.chapter.sourceOrder) }
            updatesCache = all
        }
        return cutoff == .distantPast ? all : all.filter { $0.date > cutoff }
    }
}
