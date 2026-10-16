import Foundation

/// Builds and validates the entire replacement before any durable or published mutation.
enum BackupRestorePlan {
    static func apply(_ backup: AhogeBackup, to current: PersistedState) throws -> PersistedState {
        try backup.validate()
        var next = current
        if let c = backup.collection {
            next.categories = c.categories; next.library = c.entries; next.progress = c.progress
            next.chapterStates = c.chapterStates; next.updatesSeenChapterIDs = c.seen
            next.updatesLastSeenChapterIDByMangaID = [:]
        }
        // Metadata is shared by sections. Keep existing supporting records, including
        // history-only titles, rather than treating it as exclusively library-owned.
        let incomingMangas = backup.collection?.mangas ?? backup.supportingMangas ?? []
        let incomingChapters = backup.collection?.chapters ?? backup.supportingChapters ?? [:]
        var mangas: [String: Manga] = [:]
        for manga in current.persistedMangas {
            guard mangas[manga.id] == nil else { throw BackupError.invalid("Duplicate stored title identities.") }
            mangas[manga.id] = manga
        }
        for manga in incomingMangas where backup.collection != nil || mangas[manga.id] == nil { mangas[manga.id] = manga }
        next.persistedMangas = mangas.values.sorted { $0.id < $1.id }
        for (id, incoming) in incomingChapters {
            let existing = current.knownChapters[id] ?? []
            // A supporting history import must never replace the current collection's
            // chapter metadata. A library import owns its chapters, except local files.
            let primary = backup.collection == nil ? existing : incoming
            let secondary = backup.collection == nil ? incoming : existing
            var merged = primary
            var ids = Set(primary.map(\.id))
            for chapter in secondary where ids.insert(chapter.id).inserted { merged.append(chapter) }
            for chapter in existing where chapter.isDownloaded {
                if let index = merged.firstIndex(where: { $0.id == chapter.id }) { merged[index] = chapter }
            }
            next.knownChapters[id] = merged
        }
        if let history = backup.history { next.history = history }
        if let trackers = backup.trackers { next.trackers = trackers }
        if let notes = backup.notes { next.mangaNotes = notes }
        if let p = backup.preferences {
            next.readerPreferences = p.reader; next.libraryPreferences = p.library; next.appSettings = p.app
            next.downloadPreferences = p.downloads; next.browsePreferences = p.browse; next.advancedPreferences = p.advanced
        }
        if let repositories = backup.repositories { next.packageInstallations = [:]; next.sourceRepos = repositories.map(\.url) }
        try validateReferences(next)
        return next
    }

    static func validateReferences(_ state: PersistedState) throws {
        func unique(_ ids: [String]) -> Bool { ids.allSatisfy { !$0.isEmpty } && Set(ids).count == ids.count }
        guard unique(state.persistedMangas.map(\.id)), unique(state.library.map(\.mangaID)),
            unique(state.categories.map(\.id)), unique(state.progress.map(\.mangaID)),
            unique(state.history.map { $0.id.uuidString }), unique(state.trackers.map { $0.id.uuidString }),
            unique(state.trackers.map { $0.mangaID + "::" + $0.service.rawValue })
            else { throw BackupError.invalid("Restore would leave duplicate or empty identities.") }
        let mangaIDs = Set(state.persistedMangas.map(\.id))
        guard mangaIDs.count == state.persistedMangas.count else { throw BackupError.invalid("Duplicate stored title identities.") }
        let categoryIDs = Set(state.categories.map(\.id)).union([""])
        var owners: [String: String] = [:]
        for (id, chapters) in state.knownChapters {
            guard mangaIDs.contains(id) else { throw BackupError.invalid("Stored chapters need title metadata.") }
            for chapter in chapters {
                guard chapter.mangaID == id, !chapter.id.isEmpty, owners[chapter.id] == nil else { throw BackupError.invalid("Conflicting stored chapter identities.") }
                owners[chapter.id] = id
            }
        }
        guard state.library.allSatisfy({ mangaIDs.contains($0.mangaID) && $0.categoryIDs.isSubset(of: categoryIDs) }),
            state.progress.allSatisfy({ mangaIDs.contains($0.mangaID) && owners[$0.chapterID] == $0.mangaID && $0.pageIndex >= 0 && $0.totalPages >= 0 }),
            state.chapterStates.allSatisfy({ $0.key == $0.value.chapterID && owners[$0.key] == $0.value.mangaID && $0.value.pageIndex >= 0 && $0.value.totalPages >= 0 }),
            state.history.allSatisfy({ mangaIDs.contains($0.mangaID) && owners[$0.chapterID] == $0.mangaID && $0.pageIndex >= 0 }),
            state.trackers.allSatisfy({ mangaIDs.contains($0.mangaID) }), Set(state.mangaNotes.keys).isSubset(of: mangaIDs)
            else { throw BackupError.invalid("Restore would leave records without supporting metadata. Recover the missing source metadata before restoring.") }
    }
}
