import Foundation

// Pure transfer policy; the application commits its result only after an atomic write.
enum MigrationStateTransfer {
    static func apply(state: PersistedState, plan: MigrationPlan, options: MigrationOptions) throws -> PersistedState {
        guard !state.securityPreferences.lockLibraryEdits,
            let originalEntry = state.library.first(where: { $0.mangaID == plan.original.id }) else { throw BackupError.invalid("Library locked or original removed.") }
        var next = state
        if let index = next.library.firstIndex(where: { $0.mangaID == plan.target.id }) {
            if options.categories {
                next.library[index].categoryIDs.formUnion(originalEntry.categoryIDs)
                next.library[index].categoryID = next.library[index].categoryIDs.sorted().first ?? ""
            }
        } else {
            next.library.append(LibraryEntry(mangaID: plan.target.id, categoryID: options.categories ? originalEntry.categoryID : "",
                addedAt: originalEntry.addedAt, categoryIDs: options.categories ? originalEntry.categoryIDs : [""]))
        }
        if !next.persistedMangas.contains(where: { $0.id == plan.target.id }) { next.persistedMangas.append(plan.target) }
        next.knownChapters[plan.target.id] = plan.targetChapters.map { chapter in
            Chapter(id: chapter.id, mangaID: chapter.mangaID, title: chapter.title, number: chapter.number,
                releaseDate: chapter.releaseDate, isDownloaded: false, pages: [])
        }
        if options.reading {
            for (oldID, newID) in plan.chapterMap {
                if let old = next.chapterStates[oldID] {
                    let existing = next.chapterStates[newID]
                    next.chapterStates[newID] = ChapterState(mangaID: plan.target.id, chapterID: newID,
                        isRead: old.isRead || (existing?.isRead ?? false), isBookmarked: old.isBookmarked || (existing?.isBookmarked ?? false),
                        pageIndex: existing?.pageIndex ?? 0, totalPages: existing?.totalPages ?? 0)
                }
            }
            if let old = next.progress.first(where: { $0.mangaID == plan.original.id }), let mapped = plan.chapterMap[old.chapterID],
                let targetChapter = plan.targetChapters.first(where: { $0.id == mapped }) {
                let total = targetChapter.pages.count
                let mappedProgress = ReadingProgress(mangaID: plan.target.id, chapterID: mapped, chapterTitle: targetChapter.title,
                    pageIndex: total > 0 ? min(max(old.pageIndex, 0), total - 1) : 0, totalPages: total, updatedAt: old.updatedAt)
                if !next.progress.contains(where: { $0.mangaID == plan.target.id && $0.updatedAt > old.updatedAt }) {
                    next.progress.removeAll { $0.mangaID == plan.target.id }; next.progress.append(mappedProgress)
                }
            }
        }
        if options.history {
            for old in state.history where old.mangaID == plan.original.id {
                guard let mapped = plan.chapterMap[old.chapterID], !next.history.contains(where: { $0.mangaID == plan.target.id && $0.chapterID == mapped }) else { continue }
                next.history.append(HistoryEntry(id: UUID(), mangaID: plan.target.id, chapterID: mapped, pageIndex: 0, timestamp: old.timestamp))
            }
            next.history = Array(next.history.sorted { $0.timestamp > $1.timestamp }.prefix(max(next.advancedPreferences.historyLimit, 1)))
        }
        if options.notes, let note = state.mangaNotes[plan.original.id], !note.isEmpty {
            let existing = next.mangaNotes[plan.target.id] ?? ""
            next.mangaNotes[plan.target.id] = existing.isEmpty ? note : existing == note ? existing : existing + "\n" + note
        }
        if options.tracking {
            for old in state.trackers where old.mangaID == plan.original.id {
                guard !next.trackers.contains(where: { $0.mangaID == plan.target.id && $0.service == old.service }) else { continue }
                next.trackers.append(TrackerBinding(id: UUID(), mangaID: plan.target.id, service: old.service,
                    remoteTitle: old.remoteTitle, status: old.status, progressText: old.progressText, score: old.score))
            }
        }
        if options.removeOriginal { next.library.removeAll { $0.mangaID == plan.original.id } }
        return next
    }
}
