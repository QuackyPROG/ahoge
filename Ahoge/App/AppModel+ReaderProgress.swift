// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

//
//  AppModel+ReaderProgress.swift
//  Ahoge
//

import Foundation

extension AppModel {
    func progress(for manga: Manga) -> ReadingProgress? {
        state.progress.first { $0.mangaID == manga.id }
    }

    func resumeChapter(for manga: Manga) -> Chapter? {
        if let progress = progress(for: manga) {
            if let chapter = chapter(for: progress.chapterID, in: manga) {
                return chapter
            }

            return nil
        }

        return latestChapter(for: manga)
    }

    func progressDisplayText(for manga: Manga, fallbackChapter: Chapter? = nil) -> String? {
        guard let progress = progress(for: manga) else {
            return fallbackChapter?.title
        }

        let title = chapter(for: progress.chapterID, in: manga)?.title
            ?? progress.chapterTitle
            ?? fallbackChapter?.title
            ?? "Chapter"
        let total = max(progress.totalPages, 1)
        return "\(title) • Page \(progress.pageIndex + 1) of \(total)"
    }

    var historyDisplayEntries: [(HistoryEntry, Manga, Chapter)] {
        let mangaIndex = allMangaByID()
        var chaptersByMangaID: [String: [Chapter]] = [:]

        func chaptersForManga(_ manga: Manga) -> [Chapter] {
            if let cached = chaptersByMangaID[manga.id] {
                return cached
            }
            let resolved = chapters(for: manga)
            chaptersByMangaID[manga.id] = resolved
            return resolved
        }

        return state.history
            .sorted { $0.timestamp > $1.timestamp }
            .compactMap { entry -> (HistoryEntry, Manga, Chapter)? in
                guard
                    let manga = mangaIndex[entry.mangaID],
                    let chapter = chaptersForManga(manga).first(where: { $0.id == entry.chapterID })
                else { return nil }
                return (entry, manga, chapter)
            }
    }

    func historyEntries(searchText: String) -> [(HistoryEntry, Manga, Chapter)] {
        historyDisplayEntries.filter {
            searchText.isEmpty || $0.1.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    func clearHistory() {
        state.history.removeAll()
        persist()
    }

    func clearProgress() {
        guard !state.securityPreferences.lockLibraryEdits else { return }
        state.progress.removeAll()
        persist()
    }

    func clearNotes() {
        guard !state.securityPreferences.lockLibraryEdits else { return }
        state.mangaNotes.removeAll()
        persist()
    }

    func removeHistoryEntry(_ entryID: UUID) {
        state.history.removeAll { $0.id == entryID }
        persist()
    }

    var updateFeed: [UpdateFeedItem] {
        return libraryItems(selectedCategoryID: nil).flatMap { item in
            chapters(for: item.manga).map { chapter in
                let entry = UpdateEntry(id: chapter.id, mangaID: item.id, chapterID: chapter.id,
                    sourceID: item.manga.sourceID, isBookmarked: chapterState(for: chapter.id, mangaID: item.id).isBookmarked)
                return UpdateFeedItem(id: chapter.id, manga: item.manga, chapter: chapter, entry: entry)
            }
        }.sorted { $0.chapter.releaseDate > $1.chapter.releaseDate }
    }

    func updateFeed(searchText: String, downloadedOnly: Bool) -> [UpdateFeedItem] {
        updateFeed.filter { item in
            (!downloadedOnly || item.chapter.isDownloaded) &&
            (searchText.isEmpty || item.manga.title.localizedCaseInsensitiveContains(searchText))
        }
    }

    func startChapter(for manga: Manga) -> Chapter? {
        resumeChapter(for: manga)
    }

    func nextChapter(after chapter: Chapter, in manga: Manga) -> Chapter? {
        let items = chapters(for: manga)
        guard let index = items.firstIndex(where: { $0.id == chapter.id }), index > 0 else { return nil }
        return items[index - 1]
    }

    func previousChapter(before chapter: Chapter, in manga: Manga) -> Chapter? {
        let items = chapters(for: manga)
        guard let index = items.firstIndex(where: { $0.id == chapter.id }), index + 1 < items.count else { return nil }
        return items[index + 1]
    }

    func updateProgress(for manga: Manga, chapter: Chapter, pageIndex: Int, totalPages: Int? = nil, selection: ReaderProgressSelection? = nil) {
        let previous = state.progress.first(where: { $0.mangaID == manga.id })
        var chapterState = self.chapterState(for: chapter.id, mangaID: manga.id)
        let decision = ReaderProgressPolicy.decision(pageIndex: pageIndex,
            totalPages: totalPages ?? chapter.pages.count, previousChapterMatches: previous?.chapterID == chapter.id,
            previousTotal: previous?.totalPages ?? 0, wasRead: chapterState.isRead,
            incognito: state.appSettings.incognitoMode,
            finalSourceVisible: selection?.chapterID == chapter.id && selection?.focusedIndex == pageIndex && selection?.finalSourceVisible == true)
        let effectiveTotalPages = decision.totalPages
        let boundedPage = decision.pageIndex
        let record = ReadingProgress(
            mangaID: manga.id,
            chapterID: chapter.id,
            chapterTitle: chapter.title,
            pageIndex: boundedPage,
            totalPages: effectiveTotalPages,
            updatedAt: .now
        )

        if let index = state.progress.firstIndex(where: { $0.mangaID == manga.id }) {
            state.progress[index] = record
        } else {
            state.progress.append(record)
        }

        chapterState.pageIndex = boundedPage
        chapterState.totalPages = effectiveTotalPages
        chapterState.isRead = decision.isRead
        state.chapterStates[chapter.id] = chapterState
        if chapterState.isRead {
            let completed = state.chapterStates.values.filter { $0.mangaID == manga.id && $0.isRead }.count
            for index in state.trackers.indices where state.trackers[index].mangaID == manga.id {
                let previous = Int(state.trackers[index].progressText) ?? 0
                state.trackers[index].progressText = String(max(previous, completed))
            }
        }
        if decision.writesHistory {
            let existingID = state.history.first(where: { $0.mangaID == manga.id && $0.chapterID == chapter.id })?.id ?? UUID()
            state.history.removeAll { $0.mangaID == manga.id && $0.chapterID == chapter.id }
            state.history.insert(
                HistoryEntry(id: existingID, mangaID: manga.id, chapterID: chapter.id, pageIndex: boundedPage, timestamp: .now),
                at: 0
            )
            state.history = Array(state.history.prefix(max(state.advancedPreferences.historyLimit, 1)))

            if !state.persistedMangas.contains(where: { $0.id == manga.id }) {
                state.persistedMangas.append(manga)
            }
        }
        persist()
    }
}
