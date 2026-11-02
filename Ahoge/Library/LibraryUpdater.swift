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

    /// The run in progress. Unstructured, so it does not inherit the caller's cancellation:
    /// leaving the screen that started it (and its `.refreshable` task) does not abort it.
    private var running: Task<Void, Never>?

    /// Runs an update, or waits for the one already running.
    func update(_ manga: [LibraryManga], repo: LibraryRepository, sources: SourceManager) async {
        if let running {
            await running.value
            return
        }
        guard !isRunning, !manga.isEmpty else { return }
        isRunning = true
        done = 0
        total = manga.count
        let task = Task { @MainActor in
            var errors: [String] = []
            for title in manga {
                do {
                    let source = try sources.source(title.sourceId)
                    repo.applyChapters(try await source.chapters(url: title.url), to: title)
                } catch is CancellationError {
                    // Not the title's fault.
                } catch let error as URLError where error.code == .cancelled {
                    // Not the title's fault.
                } catch {
                    errors.append("\(title.title): \(error.localizedDescription)")
                }
                self.done += 1
            }
            let now = Date()
            self.lastUpdated = now
            UserDefaults.standard.set(now, forKey: Self.lastUpdatedKey)
            self.failures = errors
            self.isRunning = false
            self.running = nil
        }
        running = task
        await task.value
    }
}
