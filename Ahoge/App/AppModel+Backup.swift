import Foundation

extension AppModel {
    private func portableRepositories() throws -> [SourceRepoRecord] {
        // Definitions may contain arbitrary publisher overrides. Reject secret-like
        // values rather than quietly exporting credentials or changing their meaning.
        for record in repoRecords {
            let definitions = record.importedSources + record.packages.flatMap(\.sources)
            let urls = [record.url] + definitions.flatMap { [$0.baseURL] + ($0.overrides["apiURL"].map { [$0] } ?? []) }
            for raw in urls {
                guard let url = URLComponents(string: raw), url.user == nil, url.password == nil,
                    url.queryItems?.contains(where: { item in ["token", "key", "auth", "secret", "password"].contains { item.name.lowercased().contains($0) } }) != true
                    else { throw BackupError.invalid("A source URL contains credentials. Remove credentials before exporting source definitions.") }
            }
            guard definitions.allSatisfy({ source in
                source.overrides.keys.allSatisfy { key in !["token", "cookie", "auth", "secret", "password", "header"].contains(where: key.lowercased().contains) }
            }) else { throw BackupError.invalid("Source definitions contain private overrides and cannot be exported.") }
        }
        return repoRecords.map { SourceRepoRecord(id: $0.id, url: $0.url, title: $0.title, fetchedAt: $0.fetchedAt,
            packages: $0.packages, importedSources: $0.importedSources, lastError: nil) }
    }

    func exportBackup(sections: Set<BackupSection>) throws -> AhogeBackup {
        var wanted: Set<String> = sections.contains(.library) ? Set(state.library.map(\.mangaID)).union(state.progress.map(\.mangaID)) : []
        if sections.contains(.history) { wanted.formUnion(state.history.map(\.mangaID)) }
        if sections.contains(.tracking) { wanted.formUnion(state.trackers.map(\.mangaID)) }
        if sections.contains(.notes) { wanted.formUnion(state.mangaNotes.keys) }
        let mangas = Array(allManga.filter { wanted.contains($0.id) }.reduce(into: [String: Manga]()) { $0[$1.id] = $1 }.values)
        let mangaIDs = Set(mangas.map(\.id))
        var portableChapters = Dictionary(uniqueKeysWithValues: mangas.map { manga in
            (manga.id, chapters(for: manga).map { chapter in
                Chapter(id: chapter.id, mangaID: chapter.mangaID, title: chapter.title, number: chapter.number,
                    releaseDate: chapter.releaseDate, isDownloaded: false, pages: [])
            })
        })
        // Preserve unresolved stable references as metadata requiring source recovery,
        // without inventing downloaded pages or reader progress.
        for progress in state.progress where mangaIDs.contains(progress.mangaID) {
            if portableChapters[progress.mangaID]?.contains(where: { $0.id == progress.chapterID }) != true {
                portableChapters[progress.mangaID, default: []].append(Chapter(id: progress.chapterID, mangaID: progress.mangaID,
                    title: progress.chapterTitle ?? "Unavailable chapter", number: 0, releaseDate: .distantPast, isDownloaded: false, pages: []))
            }
        }
        for history in state.history where mangaIDs.contains(history.mangaID) {
            if portableChapters[history.mangaID]?.contains(where: { $0.id == history.chapterID }) != true {
                portableChapters[history.mangaID, default: []].append(Chapter(id: history.chapterID, mangaID: history.mangaID,
                    title: "Unavailable chapter", number: 0, releaseDate: .distantPast, isDownloaded: false, pages: []))
            }
        }
        let portableStates = state.chapterStates.filter { value in portableChapters[value.value.mangaID]?.contains(where: { $0.id == value.key }) == true }
        let collection = BackupCollection(categories: state.categories, entries: state.library,
            mangas: mangas, chapters: portableChapters, progress: state.progress.filter { mangaIDs.contains($0.mangaID) },
            chapterStates: portableStates, seen: state.updatesSeenChapterIDs)
        let prefs = BackupPreferences(reader: state.readerPreferences, library: state.libraryPreferences,
            app: state.appSettings, downloads: state.downloadPreferences, browse: state.browsePreferences, advanced: state.advancedPreferences)
        let backup = AhogeBackup(createdAt: .now, appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            sections: sections, collection: sections.contains(.library) ? collection : nil,
            history: sections.contains(.history) ? state.history : nil, trackers: sections.contains(.tracking) ? state.trackers : nil,
            preferences: sections.contains(.preferences) ? prefs : nil, repositories: sections.contains(.sources) ? try portableRepositories() : nil,
            notes: sections.contains(.notes) ? state.mangaNotes : nil,
            supportingMangas: sections.contains(.library) || wanted.isEmpty ? nil : mangas,
            supportingChapters: sections.contains(.library) || wanted.isEmpty ? nil : portableChapters)
        try backup.validate()
        return backup
    }

    func restoreBackup(_ backup: AhogeBackup) throws {
        guard !state.securityPreferences.lockLibraryEdits else { throw BackupError.invalid("Library edits are locked.") }
        try backup.validate()
        // Include currently resolvable legacy/runtime metadata in the proposed durable
        // state so retained references also resolve after a cold launch.
        var base = state
        var knownIDs = Set(base.persistedMangas.map(\.id))
        let requiredIDs = Set(base.library.map(\.mangaID)).union(base.progress.map(\.mangaID))
            .union(base.history.map(\.mangaID)).union(base.trackers.map(\.mangaID))
            .union(base.mangaNotes.keys).union(base.knownChapters.keys)
        for manga in allManga where requiredIDs.contains(manga.id) && knownIDs.insert(manga.id).inserted { base.persistedMangas.append(manga) }
        for manga in base.persistedMangas {
            let resolved = chapters(for: manga)
            var merged = base.knownChapters[manga.id] ?? []
            var ids = Set(merged.map(\.id))
            for chapter in resolved where ids.insert(chapter.id).inserted { merged.append(chapter) }
            if !merged.isEmpty { base.knownChapters[manga.id] = merged }
        }
        let next = try BackupRestorePlan.apply(backup, to: base)
        try commitState(next, repositories: backup.repositories)
        clearCachedChapters(preservingOfflineOnly: true)
        for (id, chapters) in next.knownChapters {
            let offline = (peekCachedChapters(for: id) ?? []).filter(\.isDownloaded)
            let offlineIDs = Set(offline.map(\.id))
            setCachedChapters(chapters.filter { !offlineIDs.contains($0.id) } + offline, for: id)
        }
        clearCachedPages(); clearCachedSourceManga(); rebuildSourceRepository()
        Task { await applyCacheConfiguration() }
    }
}
