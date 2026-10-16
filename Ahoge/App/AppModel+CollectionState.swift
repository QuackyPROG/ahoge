import Foundation

extension AppModel {
    func chapterState(for chapterID: String, mangaID: String) -> ChapterState {
        guard let value = state.chapterStates[chapterID], value.mangaID == mangaID else {
            return ChapterState(mangaID: mangaID, chapterID: chapterID)
        }
        return value
    }

    func setChaptersRead(_ ids: [String], mangaID: String, read: Bool) {
        guard !state.securityPreferences.lockLibraryEdits else { return }
        for id in Set(ids) {
            var value = chapterState(for: id, mangaID: mangaID)
            value.isRead = read
            state.chapterStates[id] = value
        }
        persist()
    }

    func setChaptersBookmarked(_ ids: [String], mangaID: String, bookmarked: Bool) {
        guard !state.securityPreferences.lockLibraryEdits else { return }
        for id in Set(ids) {
            var value = chapterState(for: id, mangaID: mangaID)
            value.isBookmarked = bookmarked
            state.chapterStates[id] = value
        }
        persist()
    }

    func assignCategories(_ ids: [String], mangaIDs: [String]) {
        guard !state.securityPreferences.lockLibraryEdits else { return }
        let valid = Set(ids.filter { id in id.isEmpty || state.categories.contains(where: { $0.id == id }) })
        let membership = valid.isEmpty ? Set([""]) : valid
        let selected = Set(mangaIDs)
        for index in state.library.indices where selected.contains(state.library[index].mangaID) {
            state.library[index].categoryIDs = membership
            state.library[index].categoryID = membership.sorted().first ?? ""
        }
        persist()
    }

    func reorderCategories(from offsets: IndexSet, to destination: Int) {
        guard !state.securityPreferences.lockLibraryEdits else { return }
        let moving = offsets.sorted().map { state.categories[$0] }
        for index in offsets.sorted(by: >) { state.categories.remove(at: index) }
        let insertion = min(max(destination - offsets.filter { $0 < destination }.count, 0), state.categories.count)
        state.categories.insert(contentsOf: moving, at: insertion)
        persist()
    }

    func removeHistory(for mangaID: String) {
        state.history.removeAll { $0.mangaID == mangaID }
        persist()
    }

    func canReadChapter(_ chapter: Chapter, manga: Manga) -> Bool {
        isChapterDownloaded(manga: manga, chapter: chapter) ||
            (manga.sourceID == "local-files" && !chapter.pages.isEmpty) || supportsLiveSource(sourceID: manga.sourceID)
    }

    func refreshLibrary(categoryID: String? = nil) async {
        guard !isRefreshingLibrary else { return }
        isRefreshingLibrary = true
        defer { isRefreshingLibrary = false; persist() }
        libraryRefreshErrors = [:]
        let items = libraryItems(selectedCategoryID: categoryID)
        for item in items {
            guard !Task.isCancelled else { return }
            guard supportsLiveSource(sourceID: item.manga.sourceID) else { continue }
            let oldIDs = Set(chapters(for: item.manga).map(\.id))
            let chapters = await refreshChapters(for: item.manga)
            if let error = sourceErrors[item.manga.sourceID] { libraryRefreshErrors[item.id] = error }
            else if state.downloadPreferences.autoDownloadNewChapters {
                let new = chapters.filter { !oldIDs.contains($0.id) && (!state.downloadPreferences.unreadOnly || !chapterState(for: $0.id, mangaID: item.id).isRead) }
                enqueueDownloadAllChapters(manga: item.manga, chapters: new)
            }
        }
    }
}
