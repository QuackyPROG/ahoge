import Foundation

extension AppModel {
    func prepareMigration(original: Manga, target: Manga) async throws -> MigrationPlan {
        guard !state.securityPreferences.lockLibraryEdits, isInLibrary(original) else { throw BackupError.invalid("Original title must be in an unlocked library.") }
        guard supportsLiveSource(sourceID: target.sourceID) else { throw DiscoveryError.unsupported }
        let fetched = try await repository.chapters(sourceID: target.sourceID, manga: target)
        try Task.checkCancellation()
        let existing = chapters(for: target)
        let offline = existing.filter { isChapterDownloaded(manga: target, chapter: $0) }
        let byID = offline.reduce(into: [String: Chapter]()) { $0[$1.id] = $1 }
        let targetIDs = Set(fetched.chapters.map(\.id))
        let merged = fetched.chapters.map { byID[$0.id] ?? $0 } + offline.filter { !targetIDs.contains($0.id) }
        return try MigrationPlan.build(original: original, target: target, originalChapters: chapters(for: original), targetChapters: merged)
    }

    func applyMigration(_ plan: MigrationPlan, options: MigrationOptions) throws {
        let next = try MigrationStateTransfer.apply(state: state, plan: plan, options: options)
        try commitState(next)
        setCachedChapters(plan.targetChapters, for: plan.target.id)
    }
}
