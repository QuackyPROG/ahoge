// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

//
//  AppModel+Library.swift
//  Ahoge
//

import Foundation

extension AppModel {
    private var uncategorizedCategoryID: String { "" }

    func note(for manga: Manga) -> String {
        state.mangaNotes[manga.id, default: ""]
    }

    func saveNote(_ note: String, for manga: Manga) {
        guard !state.securityPreferences.lockLibraryEdits else { return }
        state.mangaNotes[manga.id] = note
        persist()
    }

    func libraryCategory(for manga: Manga) -> Category? {
        guard let entry = state.library.first(where: { $0.mangaID == manga.id }) else { return nil }
        return categories.first(where: { $0.id == entry.categoryID })
    }

    func isInLibrary(_ manga: Manga) -> Bool {
        state.library.contains { $0.mangaID == manga.id }
    }

    func toggleLibrary(_ manga: Manga) {
        guard !state.securityPreferences.lockLibraryEdits else { return }
        if isInLibrary(manga) {
            state.library.removeAll { $0.mangaID == manga.id }

            // Cleanup persisted backup if history doesn't mention it and the user has no offline downloads.
            let hasOfflineDownloads = peekCachedChapters(for: manga.id)?.contains(where: \.isDownloaded) ?? false
            if !hasOfflineDownloads, !state.history.contains(where: { $0.mangaID == manga.id }) {
                state.persistedMangas.removeAll { $0.id == manga.id }
            }
        } else {
            state.library.insert(
                LibraryEntry(
                    mangaID: manga.id,
                    categoryID: resolvedDefaultCategoryID(),
                    addedAt: .now
                ),
                at: 0
            )
            if !state.persistedMangas.contains(where: { $0.id == manga.id }) {
                state.persistedMangas.append(manga)
            }
            ensureMangaCached(manga)
        }
        persist()
    }

    func assignCategory(_ categoryID: String, to manga: Manga) {
        guard !state.securityPreferences.lockLibraryEdits else { return }
        guard categoryID.isEmpty || state.categories.contains(where: { $0.id == categoryID }),
            let index = state.library.firstIndex(where: { $0.mangaID == manga.id }) else { return }
        state.library[index].categoryID = categoryID
        state.library[index].categoryIDs = [categoryID]
        persist()
    }

    func categoryName(for id: String) -> String {
        if id.isEmpty {
            return "Uncategorized"
        }
        return categories.first(where: { $0.id == id })?.name ?? "Uncategorized"
    }

    func resolvedDefaultCategoryID() -> String {
        if let preferred = categories.first(where: { $0.id == state.libraryPreferences.defaultCategoryID }) {
            return preferred.id
        }
        return uncategorizedCategoryID
    }

    func addCategory(named name: String) {
        guard !state.securityPreferences.lockLibraryEdits else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let category = Category(id: UUID().uuidString, name: trimmed, systemImage: "folder")
        state.categories.append(category)
        if state.libraryPreferences.defaultCategoryID.isEmpty {
            state.libraryPreferences.defaultCategoryID = category.id
        }
        persist()
    }

    func renameCategory(_ categoryID: String, to name: String) {
        guard !state.securityPreferences.lockLibraryEdits else { return }
        guard let index = state.categories.firstIndex(where: { $0.id == categoryID }) else { return }
        state.categories[index].name = name
        persist()
    }

    func deleteCategory(_ categoryID: String) {
        guard !state.securityPreferences.lockLibraryEdits else { return }
        state.categories.removeAll { $0.id == categoryID }
        let fallback = uncategorizedCategoryID
        if state.libraryPreferences.defaultCategoryID == categoryID {
            state.libraryPreferences.defaultCategoryID = fallback
        }
        for index in state.library.indices {
            state.library[index].categoryIDs.remove(categoryID)
            if state.library[index].categoryIDs.isEmpty { state.library[index].categoryIDs = [""] }
            state.library[index].categoryID = state.library[index].categoryIDs.sorted().first ?? ""
        }
        persist()
    }

    func libraryItems(selectedCategoryID: String?, searchText: String = "", sortMode: LibrarySortMode = .recent) -> [LibraryManga] {
        let mangaIndex = allMangaByID()
        let progressIndex = progressByMangaID()
        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let downloadedOnly = state.appSettings.downloadedOnly
        var chaptersByMangaID: [String: [Chapter]] = [:]

        func chaptersForManga(_ manga: Manga) -> [Chapter] {
            if let cached = chaptersByMangaID[manga.id] {
                return cached
            }
            let resolved = chapters(for: manga)
            chaptersByMangaID[manga.id] = resolved
            return resolved
        }

        let filtered: [LibraryManga] = state.library
            .filter { selectedCategoryID == nil || $0.categoryIDs.contains(selectedCategoryID ?? "") }
            .compactMap { entry -> LibraryManga? in
                guard let manga = mangaIndex[entry.mangaID] else { return nil }
                return LibraryManga(
                    id: manga.id,
                    manga: manga,
                    entry: entry,
                    progress: progressIndex[manga.id],
                    latestChapter: chaptersForManga(manga).first
                )
            }
            .filter { item in
                normalizedSearchText.isEmpty || item.manga.title.localizedCaseInsensitiveContains(normalizedSearchText)
            }
            .filter { item in
                guard downloadedOnly else { return true }
                return chaptersForManga(item.manga).contains { isChapterDownloaded(manga: item.manga, chapter: $0) }
            }

        switch sortMode {
        case .added: return filtered.sorted { $0.entry.addedAt > $1.entry.addedAt }
        case .lastRead: return filtered.sorted { ($0.progress?.updatedAt ?? .distantPast) > ($1.progress?.updatedAt ?? .distantPast) }
        case .lastUpdate: return filtered.sorted { ($0.latestChapter?.releaseDate ?? .distantPast) > ($1.latestChapter?.releaseDate ?? .distantPast) }
        case .unreadCount: return filtered.sorted { lhs, rhs in
            chaptersForManga(lhs.manga).filter { !chapterState(for: $0.id, mangaID: lhs.id).isRead }.count >
                chaptersForManga(rhs.manga).filter { !chapterState(for: $0.id, mangaID: rhs.id).isRead }.count
        }
        case .latestChapter: return filtered.sorted { ($0.latestChapter?.number ?? 0) > ($1.latestChapter?.number ?? 0) }
        case .random: return filtered.sorted { lhs, rhs in
            // Stable for a given UTC day; repeated renders never reshuffle selection.
            let day = Int(Date().timeIntervalSince1970 / 86400)
            func rank(_ id: String) -> UInt64 { id.utf8.reduce(UInt64(day)) { ($0 &* 1099511628211) ^ UInt64($1) } }
            return rank(lhs.id) < rank(rhs.id)
        }
        case .recent:
            return filtered.sorted { ($0.progress?.updatedAt ?? $0.entry.addedAt) > ($1.progress?.updatedAt ?? $1.entry.addedAt) }
        case .alphabetical:
            return filtered.sorted { $0.manga.title < $1.manga.title }
        case .chapterCount:
            return filtered.sorted { chaptersForManga($0.manga).count > chaptersForManga($1.manga).count }
        }
    }

    func preferredLibrarySortMode() -> LibrarySortMode {
        state.libraryPreferences.sortMode
    }

    var continueReadingItems: [LibraryManga] {
        libraryItems(selectedCategoryID: nil)
            .filter { $0.progress != nil }
    }

    private func ensureMangaCached(_ manga: Manga) {
        guard manga.sourceID != "local-files" else { return }
        var items = cachedSourceManga(for: manga.sourceID) ?? []
        if !items.contains(where: { $0.id == manga.id }) {
            items.append(manga)
            setCachedSourceManga(items, for: manga.sourceID)
        }
    }
}
