import Foundation

/// Re-fetches chapter lists of library titles (Mihon's library update). Shared by Library and
/// Updates so only one runs at a time.
@MainActor
final class LibraryUpdater: ObservableObject {
    private static let lastUpdatedKey = "library.lastUpdated"

    @Published private(set) var isRunning = false
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    /// "Title: reason" for each title that failed in the last run; cleared by the alert.
    @Published var failures: [String] = []
    @Published private(set) var lastUpdated = UserDefaults.standard.object(forKey: LibraryUpdater.lastUpdatedKey) as? Date

    func update(_ manga: [LibraryManga], repo: LibraryRepository, sources: SourceManager) async {
        guard !isRunning, !manga.isEmpty else { return }
        isRunning = true
        done = 0
        total = manga.count
        var errors: [String] = []
        for title in manga {
            do {
                let source = try sources.source(title.sourceId)
                repo.applyChapters(try await source.chapters(url: title.url), to: title)
            } catch {
                errors.append("\(title.title): \(error.localizedDescription)")
            }
            done += 1
        }
        let now = Date()
        lastUpdated = now
        UserDefaults.standard.set(now, forKey: Self.lastUpdatedKey)
        failures = errors
        isRunning = false
    }
}
