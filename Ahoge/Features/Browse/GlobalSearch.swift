import Foundation

/// Searches many sources for one query, a few at a time, and keeps each source's outcome apart
/// so one failing source never hides the others (Mihon's global search).
@MainActor
final class GlobalSearch: ObservableObject {
    enum State: Equatable {
        case loading
        case done([MangaStub])
        case failed(String)
    }

    struct SourceResult: Identifiable, Equatable {
        let source: InstalledSource
        var state: State
        var id: String { source.id }

        var hasResults: Bool {
            if case .done(let manga) = state { return !manga.isEmpty }
            return false
        }
    }

    /// (source id, query) -> first page of results. The seam: tests pass a fake, the app a `SourceManager`.
    typealias Searcher = (String, String) async throws -> MangaListPage

    @Published private(set) var results: [SourceResult] = []
    private let searcher: Searcher
    private var workers: [Task<Void, Never>] = []
    private var pending: [String] = []
    /// Bumped by every run and cancel, so a late answer from an old run is dropped.
    private var generation = 0

    init(searcher: @escaping Searcher) {
        self.searcher = searcher
    }

    static func searcher(from manager: SourceManager) -> Searcher {
        { sourceId, query in try await manager.source(sourceId).search(query: query, page: 1) }
    }

    /// The sources a search covers: those the source filters leave visible, optionally only pinned
    /// ones, minus `excluding` (the source a migration starts from). Pinned sources come first.
    static func eligible(
        _ installed: [InstalledSource],
        visibility: SourceVisibility,
        pinned: [String],
        pinnedOnly: Bool,
        excluding: String? = nil
    ) -> [InstalledSource] {
        let shown = installed.filter { visibility.shows($0) && $0.id != excluding && (!pinnedOnly || pinned.contains($0.id)) }
        let first = pinned.compactMap { id in shown.first { $0.id == id } }
        let rest = shown.filter { !pinned.contains($0.id) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return first + rest
    }

    /// Starts a new search; any running one is cancelled. At most `maxConcurrent` sources run at once.
    func run(_ query: String, sources: [InstalledSource], maxConcurrent: Int = 5) {
        cancel()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            return
        }
        results = sources.map { SourceResult(source: $0, state: .loading) }
        pending = sources.map(\.id)
        let current = generation
        // Workers take ids from `pending` on the main actor, so each source is searched exactly once.
        for _ in 0..<max(1, min(maxConcurrent, pending.count)) {
            workers.append(Task { [weak self] in
                while !Task.isCancelled, let id = self?.takeNext() {
                    await self?.search(id, query: query, generation: current)
                }
            })
        }
    }

    private func takeNext() -> String? {
        pending.isEmpty ? nil : pending.removeFirst()
    }

    /// Stops pending sources; ones still loading stay `.loading`.
    func cancel() {
        generation += 1
        pending = []
        for worker in workers { worker.cancel() }
        workers = []
    }

    /// Waits for the current run to finish. For tests.
    func finished() async {
        for worker in workers { await worker.value }
    }

    private func search(_ id: String, query: String, generation current: Int) async {
        let state: State
        do {
            let page = try await searcher(id, query)
            state = .done(page.manga)
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
        guard current == generation, let index = results.firstIndex(where: { $0.id == id }) else { return }
        results[index].state = state
    }
}
