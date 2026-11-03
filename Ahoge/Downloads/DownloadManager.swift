import Combine
import Foundation
import GRDB
import Network
import UIKit

/// One chapter waiting in, or moving through, the download queue.
struct DownloadItem: Identifiable, Equatable {
    enum State: Equatable {
        case queued
        case downloading
        /// The chapter failed as a whole; it stays queued until resumed, retried or cancelled.
        case error(String)
    }

    let chapterKey: String
    let mangaKey: String
    let sourceId: String
    let chapterURL: String
    let mangaTitle: String
    let chapterName: String
    var pagesDone = 0
    var pageCount = 0
    var state: State = .queued

    var id: String { chapterKey }
    var progress: Double { pageCount > 0 ? Double(pagesDone) / Double(pageCount) : 0 }
    var isError: Bool { if case .error = state { true } else { false } }
}

enum DownloadError: LocalizedError {
    case noPages
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .noPages: "The source returned no pages."
        case .badStatus(let code): "A page failed to download (HTTP \(code))."
        }
    }
}

/// Downloads chapters for offline reading (Mihon's download manager): a persistent queue with
/// pause, resume, cancel, reorder and per-page retry, plus the index of what is on disk.
///
/// The queue runs at most `Pref.downloadConcurrentSources` chapters at once, one per source, and
/// fetches `Pref.downloadConcurrentPages` pages of each at a time. Each page is tried three times;
/// a chapter whose page still fails stops with an error and stays in the queue.
@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var queue: [DownloadItem] = []
    @Published private(set) var isPaused: Bool
    /// Downloaded chapter key → manga key; the index behind `isDownloaded`.
    @Published private var downloaded: [String: String] = [:] {
        didSet { countsByManga = Dictionary(downloaded.values.map { ($0, 1) }, uniquingKeysWith: +) }
    }
    private var countsByManga: [String: Int] = [:]

    let repo: LibraryRepository
    private let sources: SourceManager
    private let transport: HTTPTransport
    private let store: DownloadStore
    let defaults: UserDefaults
    private let retryDelay: Duration
    private let network: NetworkGate
    private var running: [String: Worker] = [:]

    private struct Worker {
        let id: UUID
        let task: Task<Void, Never>
    }

    /// Stored in `download.state`.
    private enum RowState: Int {
        case queued = 0
        case downloaded = 1
    }

    /// Page files go through this while the app is in the background (see `setBackground`).
    var backgroundTransport: HTTPTransport?
    private(set) var isInBackground = false
    private var backgroundTime: UIBackgroundTaskIdentifier = .invalid
    /// Chapters the reader finished, deleted once it closes so the open chapter stays readable.
    var pendingDeletes: [ChapterRecord] = []

    init(
        repo: LibraryRepository,
        sources: SourceManager,
        transport: HTTPTransport,
        root: URL,
        cache: URL? = nil,
        defaults: UserDefaults = .standard,
        retryDelay: Duration = .seconds(1)
    ) {
        self.repo = repo
        self.sources = sources
        self.transport = transport
        self.store = DownloadStore(root: root, cache: cache ?? root.appendingPathComponent(".cache", isDirectory: true))
        self.defaults = defaults
        self.retryDelay = retryDelay
        network = NetworkGate()
        isPaused = Pref.downloadPaused.value(in: defaults)
        load()
        repo.didMarkRead = { [weak self] chapters in self?.chaptersMarkedRead(chapters) }
        network.onChange = { [weak self] in self?.networkPolicyChanged() }
        network.start()
        schedule()
    }

    /// Application Support/Downloads, left out of iCloud and device backups.
    static func defaultRoot() -> URL {
        var url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }

    static func defaultCache() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ChapterCache", isDirectory: true)
    }

    // MARK: Queue

    /// Adds chapters to the end of the queue; downloaded and queued ones are skipped, failed ones retried.
    func enqueue(_ chapters: [ChapterRecord]) {
        var changed = false
        for chapter in chapters where downloaded[chapter.key] == nil {
            if let index = queue.firstIndex(where: { $0.chapterKey == chapter.key }) {
                if queue[index].isError {
                    queue[index].state = .queued
                    changed = true
                }
                continue
            }
            queue.append(item(for: chapter))
            changed = true
        }
        guard changed else { return }
        persistQueue()
        schedule()
    }

    func pause() {
        guard !isPaused else { return }
        isPaused = true
        Pref.downloadPaused.set(true, in: defaults)
        stopWorkers()
    }

    /// Starts the queue again; failed chapters are retried.
    func resume() {
        isPaused = false
        Pref.downloadPaused.set(false, in: defaults)
        for index in queue.indices where queue[index].isError { queue[index].state = .queued }
        schedule()
    }

    /// Removes chapters from the queue and the pages they had so far.
    func cancel(_ chapterKeys: [String]) {
        let keys = Set(chapterKeys)
        let removed = queue.filter { keys.contains($0.chapterKey) }
        guard !removed.isEmpty else { return }
        for item in removed {
            running[item.chapterKey]?.task.cancel()
            running[item.chapterKey] = nil
            store.remove(location(item))
        }
        queue.removeAll { keys.contains($0.chapterKey) }
        persistQueue()
        schedule()
    }

    func move(_ chapterKey: String, to index: Int) {
        guard let from = queue.firstIndex(where: { $0.chapterKey == chapterKey }) else { return }
        let item = queue.remove(at: from)
        queue.insert(item, at: min(max(index, 0), queue.count))
        persistQueue()
        schedule()
    }

    /// Deletes downloaded files and rows, and drops the chapters from the queue.
    func delete(_ chapters: [ChapterRecord]) {
        guard !chapters.isEmpty else { return }
        cancel(chapters.map(\.key))
        for chapter in chapters {
            store.remove(DownloadStore.Location(sourceId: chapter.sourceId, mangaKey: chapter.mangaKey, chapterKey: chapter.key))
            if downloaded[chapter.key] != nil { downloaded[chapter.key] = nil }
        }
        let keys = chapters.map(\.key)
        repo.write { db in
            for key in keys { try db.execute(sql: "DELETE FROM download WHERE chapterKey = ?", arguments: [key]) }
        }
    }

    // MARK: Index

    func isDownloaded(_ chapterKey: String) -> Bool { downloaded[chapterKey] != nil }

    /// How many chapters of a manga are downloaded.
    func downloadedCount(mangaKey: String) -> Int { countsByManga[mangaKey] ?? 0 }

    /// The page files of a downloaded chapter in order, or nil when it is not downloaded.
    func localPages(_ chapterKey: String) -> [URL]? {
        guard let mangaKey = downloaded[chapterKey] else { return nil }
        return store.localPages(DownloadStore.Location(sourceId: ChapterRecord.sourceId(ofKey: chapterKey), mangaKey: mangaKey, chapterKey: chapterKey))
    }

    /// Rebuilds the downloaded rows from what is on disk (Mihon's "Reindex downloads"). Chapters
    /// still being written (`.partial`) do not count.
    func reindex() {
        let candidates = (try? repo.db.read { db in
            try Row.fetchAll(db, sql: "SELECT chapter.key AS chapterKey, chapter.mangaKey AS mangaKey, manga.sourceId AS sourceId FROM chapter JOIN manga ON manga.key = chapter.mangaKey")
        }) ?? []
        let folders = store.mangaFolders()
        let queued = Set(queue.map(\.chapterKey))
        var found: [(location: DownloadStore.Location, pages: Int, bytes: Int64)] = []
        for row in candidates {
            let location = DownloadStore.Location(sourceId: row["sourceId"], mangaKey: row["mangaKey"], chapterKey: row["chapterKey"])
            guard !queued.contains(location.chapterKey), folders.contains(store.mangaFolder(location)),
                  let done = store.completed(location) else { continue }
            found.append((location, done.pages, done.bytes))
        }
        let now = Date()
        repo.write { db in
            try db.execute(sql: "DELETE FROM download WHERE state = ?", arguments: [RowState.downloaded.rawValue])
            for entry in found {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO download (chapterKey, mangaKey, state, pageCount, bytes, dateAdded) VALUES (?, ?, ?, ?, ?, ?)",
                    arguments: [entry.location.chapterKey, entry.location.mangaKey, RowState.downloaded.rawValue, entry.pages, entry.bytes, now]
                )
            }
        }
        downloaded = Dictionary(found.map { ($0.location.chapterKey, $0.location.mangaKey) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Storage

    /// Bytes used by downloads (archives and folders).
    func downloadsSize() -> Int64 {
        let total = DownloadStore.size(of: store.root)
        return store.cache.path.hasPrefix(store.root.path) ? total - DownloadStore.size(of: store.cache) : total
    }

    /// Bytes used by unpacked CBZ chapters.
    func chapterCacheSize() -> Int64 { DownloadStore.size(of: store.cache) }

    func clearChapterCache() { store.clearCache() }

    /// Both sizes, measured off the main thread.
    func storageUsage() async -> (downloads: Int64, chapterCache: Int64) {
        let store = self.store
        return await Task.detached(priority: .utility) { () -> (downloads: Int64, chapterCache: Int64) in
            let cache = DownloadStore.size(of: store.cache)
            let total = DownloadStore.size(of: store.root)
            return (store.cache.path.hasPrefix(store.root.path) ? total - cache : total, cache)
        }.value
    }

    // MARK: Tests and background work

    /// Returns once nothing is downloading (queued chapters held back by pause or Wi-Fi stay queued).
    func waitUntilIdle() async {
        while let worker = running.values.first {
            await worker.task.value
        }
    }

    /// Hands page files to `backgroundTransport` while the app is away, and back on return.
    /// Running chapters restart on the other transport; pages already saved are kept.
    func setBackground(_ background: Bool) {
        guard background != isInBackground else { return }
        isInBackground = background
        guard backgroundTransport != nil, !running.isEmpty else { return endBackgroundTime() }
        stopWorkers()
        schedule()
        guard background else { return endBackgroundTime() }
        // Enough time to resolve page lists and hand the requests to the background session.
        backgroundTime = UIApplication.shared.beginBackgroundTask(withName: "Downloads") { [weak self] in
            MainActor.assumeIsolated { self?.endBackgroundTime() }
        }
        Task {
            await waitUntilIdle()
            endBackgroundTime()
        }
    }

    private func endBackgroundTime() {
        guard backgroundTime != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTime)
        backgroundTime = .invalid
    }

    /// Call after `Pref.downloadOnlyOnWiFi` changes.
    func networkPolicyChanged() {
        if network.allows(onlyWiFi: Pref.downloadOnlyOnWiFi.value(in: defaults)) {
            schedule()
        } else {
            stopWorkers()
        }
    }

    // MARK: Worker

    private func schedule() {
        guard !isPaused, network.allows(onlyWiFi: Pref.downloadOnlyOnWiFi.value(in: defaults)) else { return }
        let limit = max(1, Pref.downloadConcurrentSources.value(in: defaults))
        var busy = Set(queue.filter { running[$0.chapterKey] != nil }.map(\.sourceId))
        for item in queue where item.state == .queued && running[item.chapterKey] == nil {
            guard running.count < limit else { return }
            guard busy.insert(item.sourceId).inserted else { continue }
            start(item.chapterKey)
        }
    }

    private func start(_ key: String) {
        guard let index = queue.firstIndex(where: { $0.chapterKey == key }) else { return }
        queue[index].state = .downloading
        let id = UUID()
        // Runs on the main actor after this returns, so `running` already holds it.
        let task = Task { [weak self] in await self?.run(key, worker: id) }
        running[key] = Worker(id: id, task: task)
    }

    /// Cancels running chapters and puts them back as queued.
    private func stopWorkers() {
        for (key, worker) in running {
            worker.task.cancel()
            if let index = queue.firstIndex(where: { $0.chapterKey == key }) { queue[index].state = .queued }
        }
        running = [:]
    }

    private func isCurrent(_ key: String, _ worker: UUID) -> Bool { running[key]?.id == worker && !Task.isCancelled }

    private func run(_ key: String, worker: UUID) async {
        defer {
            if running[key]?.id == worker { running[key] = nil }
            schedule()
        }
        guard let item = queue.first(where: { $0.chapterKey == key }) else { return }
        let location = self.location(item)
        do {
            let pages = try await sources.source(item.sourceId).pages(url: item.chapterURL)
            guard isCurrent(key, worker) else { return }
            guard !pages.isEmpty else { throw DownloadError.noPages }
            let directory = try store.begin(location)
            let saved = store.existingPages(in: directory)
            setProgress(key, done: pages.indices.filter { saved.contains($0) }.count, total: pages.count)

            var pending = pages.enumerated().filter { !saved.contains($0.offset) }.map { (index: $0.offset, page: $0.element) }
            pending.reverse()
            let limit = max(1, Pref.downloadConcurrentPages.value(in: defaults))
            let transport = isInBackground ? backgroundTransport ?? self.transport : self.transport
            let onlyWiFi = Pref.downloadOnlyOnWiFi.value(in: defaults)
            let delay = retryDelay
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<limit {
                    guard let next = pending.popLast() else { break }
                    group.addTask { try await Self.fetchPage(next.page, index: next.index, into: directory, transport: transport, onlyWiFi: onlyWiFi, delay: delay) }
                }
                while try await group.next() != nil {
                    guard isCurrent(key, worker) else { throw CancellationError() }
                    advance(key)
                    if let next = pending.popLast() {
                        group.addTask { try await Self.fetchPage(next.page, index: next.index, into: directory, transport: transport, onlyWiFi: onlyWiFi, delay: delay) }
                    }
                }
            }
            guard isCurrent(key, worker) else { return }
            let zip = Pref.saveAsCBZ.value(in: defaults)
            let store = self.store
            let result = try await Task.detached(priority: .utility) { try store.finish(location, zip: zip) }.value
            guard isCurrent(key, worker) else { return }
            completed(item, pages: result.pages, bytes: result.bytes)
        } catch {
            guard isCurrent(key, worker), let index = queue.firstIndex(where: { $0.chapterKey == key }) else { return }
            queue[index].state = .error(error.localizedDescription)
        }
    }

    /// One page: three tries, waiting longer after each failure.
    private nonisolated static func fetchPage(_ page: SourcePage, index: Int, into directory: URL, transport: HTTPTransport, onlyWiFi: Bool, delay: Duration) async throws {
        guard let url = URL(string: page.url) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(HTTPClient.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        for (name, value) in page.headers { request.setValue(value, forHTTPHeaderField: name) }
        request.allowsExpensiveNetworkAccess = !onlyWiFi
        var attempt = 0
        while true {
            do {
                let (data, response) = try await transport.send(request)
                guard (200..<300).contains(response.statusCode) else { throw DownloadError.badStatus(response.statusCode) }
                _ = try DownloadStore.writePage(data, index: index, in: directory)
                return
            } catch {
                attempt += 1
                if attempt >= 3 || Task.isCancelled { throw error }
                try await Task.sleep(for: delay * attempt)
            }
        }
    }

    private func setProgress(_ key: String, done: Int, total: Int) {
        guard let index = queue.firstIndex(where: { $0.chapterKey == key }) else { return }
        queue[index].pagesDone = done
        queue[index].pageCount = total
    }

    private func advance(_ key: String) {
        guard let index = queue.firstIndex(where: { $0.chapterKey == key }) else { return }
        queue[index].pagesDone += 1
    }

    private func completed(_ item: DownloadItem, pages: Int, bytes: Int64) {
        queue.removeAll { $0.chapterKey == item.chapterKey }
        downloaded[item.chapterKey] = item.mangaKey
        let now = Date()
        repo.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO download (chapterKey, mangaKey, state, pageCount, bytes, dateAdded) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: [item.chapterKey, item.mangaKey, RowState.downloaded.rawValue, pages, bytes, now]
            )
        }
    }

    // MARK: Persistence

    /// Reads the index and the saved queue (rows in `download`, queued ones ordered by `dateAdded`).
    private func load() {
        let rows = (try? repo.db.read { db in
            try Row.fetchAll(db, sql: "SELECT chapterKey, mangaKey, state FROM download ORDER BY dateAdded")
        }) ?? []
        var index: [String: String] = [:]
        var missing: [String] = []
        for row in rows {
            let key: String = row["chapterKey"]
            let mangaKey: String = row["mangaKey"]
            if row["state"] as Int == RowState.downloaded.rawValue {
                index[key] = mangaKey
            } else if let chapter = repo.manga(key: mangaKey)?.chapters.first(where: { $0.key == key }) {
                queue.append(item(for: chapter))
            } else {
                missing.append(key)
            }
        }
        downloaded = index
        if !missing.isEmpty {
            repo.write { db in
                for key in missing { try db.execute(sql: "DELETE FROM download WHERE chapterKey = ?", arguments: [key]) }
            }
        }
    }

    /// Rewrites the queued rows in queue order; `dateAdded` carries the order.
    private func persistQueue() {
        let items = queue.map { ($0.chapterKey, $0.mangaKey) }
        let base = Date()
        repo.write { db in
            try db.execute(sql: "DELETE FROM download WHERE state = ?", arguments: [RowState.queued.rawValue])
            for (offset, item) in items.enumerated() {
                // A chapter row deleted meanwhile fails its foreign key; skip it, keep the rest.
                try? db.execute(
                    sql: "INSERT OR IGNORE INTO download (chapterKey, mangaKey, state, pageCount, bytes, dateAdded) VALUES (?, ?, ?, 0, 0, ?)",
                    arguments: [item.0, item.1, RowState.queued.rawValue, base.addingTimeInterval(Double(offset))]
                )
            }
        }
    }

    private func item(for chapter: ChapterRecord) -> DownloadItem {
        let manga = chapter.manga ?? repo.manga(key: chapter.mangaKey)
        return DownloadItem(
            chapterKey: chapter.key,
            mangaKey: chapter.mangaKey,
            sourceId: manga?.sourceId ?? chapter.sourceId,
            chapterURL: chapter.url,
            mangaTitle: manga?.title ?? "",
            chapterName: chapter.name
        )
    }

    private func location(_ item: DownloadItem) -> DownloadStore.Location {
        DownloadStore.Location(sourceId: item.sourceId, mangaKey: item.mangaKey, chapterKey: item.chapterKey)
    }
}

extension ChapterRecord {
    /// The source id, the part of the key before the URL (`LibraryManga.makeKey`).
    static func sourceId(ofKey key: String) -> String { String(key.prefix { $0 != "\n" }) }
    var sourceId: String { Self.sourceId(ofKey: key) }
}

/// Holds downloads back on cellular when "Only on Wi-Fi" is on. An unknown or offline path does not
/// block: requests then fail and the chapter shows the error, as in Mihon.
@MainActor
private final class NetworkGate {
    private var isExpensive = false
    var onChange: (() -> Void)?
    private let monitor = NWPathMonitor()

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let expensive = path.status == .satisfied && path.isExpensive
            Task { @MainActor in
                guard let self, self.isExpensive != expensive else { return }
                self.isExpensive = expensive
                self.onChange?()
            }
        }
        monitor.start(queue: DispatchQueue(label: "ahoge.downloads.network"))
    }

    func allows(onlyWiFi: Bool) -> Bool { !(onlyWiFi && isExpensive) }

    deinit { monitor.cancel() }
}
