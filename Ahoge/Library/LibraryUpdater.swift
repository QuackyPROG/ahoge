import Foundation
import OSLog

/// Re-fetches chapter lists of library titles (Mihon's library update). Shared by Library and
/// Updates so only one runs at a time.
@MainActor
final class LibraryUpdater: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    /// "Title: reason" for each title that failed in the last run; cleared by the alert.
    @Published var failures: [String] = []
    @Published private(set) var lastUpdated = Pref.libraryLastUpdated.value()
    /// Told about chapters each update finds ("Download new chapters").
    weak var downloads: DownloadManager?

    /// The run in progress. Unstructured, so it does not inherit the caller's cancellation:
    /// leaving the screen that started it (and its `.refreshable` task) does not abort it.
    private var running: Task<Void, Never>?

    /// Who asked for the update: the background task, or the user.
    enum Trigger {
        case automatic
        /// A pull-to-refresh or menu item: keeps the skip rules but ignores "not due yet".
        case manual
    }

    /// Stops the run in progress after the title being fetched; what was fetched stays saved.
    func cancel() { running?.cancel() }

    /// Runs an update, or waits for the one already running.
    func update(_ manga: [LibraryManga], repo: LibraryRepository, sources: SourceManager, trigger: Trigger = .manual) async {
        if let running {
            await running.value
            return
        }
        let rules = UpdateRules.current(categories: repo.categories)
        let started = Date()
        var queue = manga.filter { title in
            let reason = UpdatePolicy.decide(title, categories: repo.categoryIds(of: title), rules: rules, now: started)
            return reason == nil || (trigger == .manual && reason == .notDue)
        }
        // Background runs can be cut short, so the titles checked longest ago go first.
        if trigger == .automatic { queue.sort { ($0.lastChapterFetch ?? .distantPast) < ($1.lastChapterFetch ?? .distantPast) } }
        guard !isRunning, !queue.isEmpty else { return }
        isRunning = true
        done = 0
        total = queue.count
        let refreshMetadata = Pref.updateRefreshMetadata.value()
        let matchTitles = Pref.updateMatchTitles.value()
        let titles = queue
        let task = Task { @MainActor in
            var errors: [String] = []
            var withNew: [(manga: LibraryManga, chapters: [ChapterRecord])] = []
            for title in titles {
                if Task.isCancelled { break }
                do {
                    let source = try sources.source(title.sourceId)
                    // A failing details call must not stop the chapters from updating.
                    if refreshMetadata, let details = try? await source.details(url: title.url) {
                        repo.upsert(sourceId: title.sourceId, url: title.url, details: details, keepTitle: !matchTitles)
                    }
                    let before = Set(title.chapters.map(\.key))
                    repo.applyChapters(try await source.chapters(url: title.url), to: title)
                    // A title's first fetch is not "new chapters".
                    let found = before.isEmpty ? [] : title.chapters.filter { !before.contains($0.key) }
                    if !found.isEmpty {
                        self.downloads?.chaptersFound(found, in: title)
                        withNew.append((title, found))
                    }
                } catch is CancellationError {
                    // Not the title's fault.
                } catch let error as URLError where error.code == .cancelled {
                    // Not the title's fault.
                } catch {
                    errors.append("\(title.title): \(error.localizedDescription)")
                    AppLog.logger.error("Update failed for \(title.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
                self.done += 1
            }
            let now = Date()
            self.lastUpdated = now
            Pref.libraryLastUpdated.set(now)
            self.failures = errors
            self.isRunning = false
            self.running = nil
            await UpdateNotifier.notify(newChapters: withNew)
            if trigger == .automatic, !errors.isEmpty { await UpdateNotifier.notifyFailures(count: errors.count) }
        }
        running = task
        await task.value
    }
}
