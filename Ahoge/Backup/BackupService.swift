import Foundation

/// What a restore did, for the report sheet.
struct RestoreReport: Equatable {
    var restoredManga = 0
    /// Names (or ids) of sources the backup's titles use that are not installed on this device.
    var missingSources: [String] = []
    /// Repositories that could not be added.
    var failedRepos: [String] = []
}

/// Turns the app's data into a `Backup` and merges a `Backup` back in (Mihon's restore behaviour).
@MainActor
enum BackupService {
    static func snapshot(of repo: LibraryRepository, store: ExtensionStore, defaults: UserDefaults, now: Date = Date()) -> Backup {
        let history = repo.historyByChapter()
        let excluded = repo.excludedScanlatorsByManga()
        let categoryNames = repo.categories.sorted { $0.sort < $1.sort }

        let manga = repo.mangaForBackup().map { manga -> BackupManga in
            let ids = repo.categoryIds(of: manga)
            return BackupManga(
                sourceId: manga.sourceId,
                url: manga.url,
                title: manga.title,
                cover: manga.coverUrl,
                author: manga.author,
                artist: manga.artist,
                summary: manga.summary,
                genres: manga.genres,
                status: manga.status,
                inLibrary: manga.inLibrary,
                dateAdded: manga.dateAdded,
                notes: manga.notes,
                updateInterval: manga.updateInterval,
                categories: categoryNames.filter { ids.contains($0.id) }.map(\.name),
                excludedScanlators: excluded[manga.key] ?? [],
                chapters: manga.sortedChapters.map { chapter in
                    BackupChapter(
                        url: chapter.url,
                        name: chapter.name,
                        number: chapter.number,
                        scanlator: chapter.scanlator,
                        dateUpload: chapter.dateUpload,
                        sourceOrder: chapter.sourceOrder,
                        read: chapter.read,
                        bookmark: chapter.bookmark,
                        lastPageRead: chapter.lastPageRead,
                        lastRead: history[chapter.key]?.lastRead,
                        timeRead: history[chapter.key]?.timeRead ?? 0
                    )
                }
            )
        }

        var preferences: [String: PreferenceValue] = [:]
        for name in Pref.backupNames {
            if let value = PreferenceValue(stored: defaults.object(forKey: name)) { preferences[name] = value }
        }

        return Backup(
            createdAt: now,
            manga: manga,
            categories: categoryNames.enumerated().map { index, category in
                BackupCategory(name: category.name, sort: index, flags: category.flags, sortMode: category.sortMode)
            },
            repos: store.repos.map(\.url),
            installedSourceIds: store.installed.map(\.id),
            preferences: preferences
        )
    }

    /// Adds and merges; nothing already on the device is removed. Repositories are added first and
    /// sources the backup had installed are installed when a repository lists them.
    static func restore(_ backup: Backup, into repo: LibraryRepository, store: ExtensionStore, defaults: UserDefaults) async -> RestoreReport {
        var report = RestoreReport()

        for url in backup.repos where !store.repos.contains(where: { $0.url == url }) {
            do { try await store.addRepo(url) } catch { report.failedRepos.append(url) }
        }
        for id in backup.installedSourceIds where !store.installed.contains(where: { $0.id == id }) {
            if let row = store.rows().first(where: { $0.source.id == id && $0.state == .available }) {
                try? await store.install(row.source, from: row.repoURL)
            }
        }

        for category in backup.categories.sorted(by: { $0.sort < $1.sort }) {
            repo.categoryId(named: category.name, creating: category)
        }
        for item in backup.manga {
            repo.restoreManga(item)
            report.restoredManga += 1
        }

        for (name, value) in backup.preferences where Pref.backupNames.contains(name) {
            defaults.set(value.stored, forKey: name)
        }

        let installed = Set(store.installed.map(\.id))
        var missing: [String: String] = [:]
        for item in backup.manga where !installed.contains(item.sourceId) {
            missing[item.sourceId] = item.sourceName ?? item.sourceId
        }
        report.missingSources = missing.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return report
    }
}
