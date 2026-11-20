import GRDB
import XCTest
@testable import Ahoge

@MainActor
final class DownloadManagerTests: XCTestCase {
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
    private var root: URL!
    private var cache: URL!
    private var defaults: UserDefaults!

    override func setUp() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        root = base.appendingPathComponent("downloads")
        cache = base.appendingPathComponent("cache")
        defaults = UserDefaults(suiteName: "download-tests-\(UUID().uuidString)")!
        Pref.downloadOnlyOnWiFi.set(false, in: defaults)
    }

    /// Answers every page with JPEG bytes, except URLs in `failing`, which get a 500.
    private func transport(failing: Set<String> = []) -> StubTransport {
        let page = jpeg
        return StubTransport { request in
            failing.contains(request.url!.absoluteString) ? (500, [:], Data(), nil) : (200, [:], page, nil)
        }
    }

    private func manager(_ repo: LibraryRepository, _ sources: SourceManager, _ transport: StubTransport) -> DownloadManager {
        DownloadManager(repo: repo, sources: sources, transport: transport, root: root, cache: cache, defaults: defaults, retryDelay: .zero)
    }

    /// File names under the downloads folder, sorted.
    private func filesOnDisk() -> [String] {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        var names: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { names.append(url.lastPathComponent) }
        }
        return names.sorted()
    }

    private func rowCount(_ repo: LibraryRepository, state: Int) throws -> Int {
        try repo.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM download WHERE state = ?", arguments: [state]) ?? 0 }
    }

    private func downloadRows(_ repo: LibraryRepository) throws -> [Row] {
        try repo.db.read { try Row.fetchAll($0, sql: "SELECT chapterKey, pageCount FROM download") }
    }

    /// The chapter URL of each page request, with repeats collapsed: the order chapters downloaded in.
    private func chapterOrder(_ stub: StubTransport) -> [String] {
        var order: [String] = []
        for request in stub.requests {
            let chapter = request.url!.deletingLastPathComponent().path
            if order.last != chapter { order.append(chapter) }
        }
        return order
    }

    func testDownloadsAChapterWithItsHeadersAndIndexesIt() async throws {
        let repo = try LibraryRepository.inMemory()
        let manga = SourceFixture.manga(in: repo, chapters: 2)
        let stub = transport()
        let downloads = manager(repo, SourceManager(extensions: try SourceFixture.extensions()), stub)

        downloads.enqueue([manga.chapter(1)])
        await downloads.waitUntilIdle()

        XCTAssertTrue(downloads.isDownloaded(manga.chapter(1).key))
        XCTAssertFalse(downloads.isDownloaded(manga.chapter(2).key))
        let pages = await downloads.localPages(manga.chapter(1).key)
        XCTAssertEqual(pages?.map(\.lastPathComponent), ["001.jpg", "002.jpg", "003.jpg"])
        XCTAssertEqual(downloads.downloadedCount(mangaKey: manga.key), 1)
        XCTAssertTrue(downloads.queue.isEmpty)
        XCTAssertEqual(try rowCount(repo, state: 1), 1)
        XCTAssertEqual(Set(stub.requests.map { $0.url!.absoluteString }), ["https://img.test/c/1/1.jpg", "https://img.test/c/1/2.jpg", "https://img.test/c/1/3.jpg"])
        XCTAssertEqual(stub.requests.map { $0.value(forHTTPHeaderField: "Referer") }, ["https://img.test/", "https://img.test/", "https://img.test/"])
        XCTAssertEqual(filesOnDisk(), ["001.jpg", "002.jpg", "003.jpg"])

        downloads.enqueue([manga.chapter(1)])
        XCTAssertTrue(downloads.queue.isEmpty, "a downloaded chapter is not queued again")
    }

    func testPausedQueueFetchesNothingUntilResumed() async throws {
        let repo = try LibraryRepository.inMemory()
        let manga = SourceFixture.manga(in: repo, chapters: 1)
        let stub = transport()
        let downloads = manager(repo, SourceManager(extensions: try SourceFixture.extensions()), stub)

        downloads.pause()
        downloads.enqueue([manga.chapter(1)])
        await downloads.waitUntilIdle()
        XCTAssertTrue(downloads.isPaused)
        XCTAssertEqual(downloads.queue.map(\.state), [.queued])
        XCTAssertTrue(stub.requests.isEmpty)

        downloads.resume()
        await downloads.waitUntilIdle()
        XCTAssertTrue(downloads.isDownloaded(manga.chapter(1).key))
        XCTAssertEqual(stub.requests.count, 3)
    }

    func testQueueRunsInOrderAndMoveReordersIt() async throws {
        let repo = try LibraryRepository.inMemory()
        let manga = SourceFixture.manga(in: repo, chapters: 3)
        let stub = transport()
        let downloads = manager(repo, SourceManager(extensions: try SourceFixture.extensions()), stub)

        downloads.pause()
        downloads.enqueue([manga.chapter(1), manga.chapter(2), manga.chapter(3)])
        downloads.move(manga.chapter(3).key, to: 0)
        XCTAssertEqual(downloads.queue.map(\.chapterURL), ["/c/3", "/c/1", "/c/2"])

        downloads.resume()
        await downloads.waitUntilIdle()
        // One source downloads one chapter at a time, in queue order.
        XCTAssertEqual(chapterOrder(stub), ["/c/3", "/c/1", "/c/2"])
    }

    func testAPageFailingThreeTimesFailsItsChapterAndOthersContinue() async throws {
        let repo = try LibraryRepository.inMemory()
        let manga = SourceFixture.manga(in: repo, chapters: 2)
        let stub = transport(failing: ["https://img.test/c/1/2.jpg"])
        let downloads = manager(repo, SourceManager(extensions: try SourceFixture.extensions()), stub)

        downloads.enqueue([manga.chapter(1), manga.chapter(2)])
        await downloads.waitUntilIdle()

        XCTAssertEqual(stub.requests.filter { $0.url!.absoluteString == "https://img.test/c/1/2.jpg" }.count, 3)
        XCTAssertEqual(downloads.queue.map(\.chapterURL), ["/c/1"])
        XCTAssertEqual(downloads.queue.first?.isError, true)
        XCTAssertFalse(downloads.isDownloaded(manga.chapter(1).key))
        XCTAssertTrue(downloads.isDownloaded(manga.chapter(2).key))
    }

    func testCancelRemovesPartialFiles() async throws {
        let repo = try LibraryRepository.inMemory()
        let manga = SourceFixture.manga(in: repo, chapters: 1)
        let downloads = manager(repo, SourceManager(extensions: try SourceFixture.extensions()), transport(failing: ["https://img.test/c/1/3.jpg"]))

        downloads.enqueue([manga.chapter(1)])
        await downloads.waitUntilIdle()
        XCTAssertEqual(filesOnDisk(), [".pages", ".partial", "001.jpg", "002.jpg"])

        downloads.cancel([manga.chapter(1).key])
        XCTAssertTrue(downloads.queue.isEmpty)
        XCTAssertEqual(filesOnDisk(), [])
        XCTAssertEqual(try rowCount(repo, state: 0), 0)
    }

    func testResumeAfterThePageListChangedKeepsOnlyTheNewPages() async throws {
        let repo = try LibraryRepository.inMemory()
        let manga = SourceFixture.manga(in: repo, chapters: 1)
        let chapter = manga.chapter(1)
        let location = DownloadStore.Location(sourceId: SourceFixture.sourceId, mangaKey: manga.key, chapterKey: chapter.key)
        let directory = try DownloadStore(root: root, cache: cache).begin(location, pages: (1...3).map { "https://img.test/c/1/\($0).jpg" })
        for name in ["001.jpg", "002.jpg", "003.jpg"] { try jpeg.write(to: directory.appendingPathComponent(name)) }
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let page = jpeg
        let stub = StubTransport { request in (200, [:], request.url!.lastPathComponent == "1.jpg" ? png : page, nil) }
        let downloads = manager(repo, SourceManager(extensions: try SourceFixture.extensions(pageCount: 2)), stub)

        downloads.enqueue([chapter])
        await downloads.waitUntilIdle()

        XCTAssertTrue(downloads.isDownloaded(chapter.key))
        XCTAssertEqual(filesOnDisk(), ["001.png", "002.jpg"])
        XCTAssertEqual(try downloadRows(repo).map { $0["pageCount"] as Int }, [2])
    }

    func testCancelWhileZippingLeavesNothing() async throws {
        Pref.saveAsCBZ.set(true, in: defaults)
        let repo = try LibraryRepository.inMemory()
        let manga = SourceFixture.manga(in: repo, chapters: 1)
        let downloads = manager(repo, SourceManager(extensions: try SourceFixture.extensions()), transport())
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        DownloadStore.willPlaceArchive = {
            entered.signal()
            release.wait()
        }
        defer { DownloadStore.willPlaceArchive = nil }

        downloads.enqueue([manga.chapter(1)])
        var waited = 0
        while entered.wait(timeout: .now()) == .timedOut, waited < 1000 {
            waited += 1
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertLessThan(waited, 1000, "the download never reached zipping")
        downloads.cancel([manga.chapter(1).key])
        release.signal()
        await downloads.waitUntilIdle()
        // The zipping task outlives the cancelled worker; give it time to finish.
        var tries = 0
        while !filesOnDisk().isEmpty, tries < 200 {
            tries += 1
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(filesOnDisk(), [])
        downloads.reindex()
        XCTAssertFalse(downloads.isDownloaded(manga.chapter(1).key))
    }

    func testReindexRestoresRowsFromDiskAndIgnoresPartialChapters() async throws {
        let repo = try LibraryRepository.inMemory()
        let manga = SourceFixture.manga(in: repo, chapters: 2)
        let sources = SourceManager(extensions: try SourceFixture.extensions())
        let first = manager(repo, sources, transport(failing: ["https://img.test/c/2/1.jpg"]))
        first.enqueue([manga.chapter(1), manga.chapter(2)])
        await first.waitUntilIdle()
        XCTAssertTrue(first.isDownloaded(manga.chapter(1).key))

        repo.write { try $0.execute(sql: "DELETE FROM download") }
        let downloads = manager(repo, sources, transport())
        XCTAssertFalse(downloads.isDownloaded(manga.chapter(1).key))

        downloads.reindex()
        XCTAssertTrue(downloads.isDownloaded(manga.chapter(1).key))
        XCTAssertFalse(downloads.isDownloaded(manga.chapter(2).key))
        XCTAssertEqual(try rowCount(repo, state: 1), 1)
        let pages = await downloads.localPages(manga.chapter(1).key)
        XCTAssertEqual(pages?.count, 3)
    }

    func testReindexDeletesFoldersAndArchivesWithNoChapter() async throws {
        let repo = try LibraryRepository.inMemory()
        let manga = SourceFixture.manga(in: repo, chapters: 2)
        let downloads = manager(repo, SourceManager(extensions: try SourceFixture.extensions()), transport())
        downloads.enqueue([manga.chapter(1)])
        await downloads.waitUntilIdle()
        downloads.pause()
        downloads.enqueue([manga.chapter(2)])
        let folder = root.appendingPathComponent(SourceFixture.sourceId).appendingPathComponent(DownloadStore.hash(manga.key))
        let fm = FileManager.default
        let orphan = folder.appendingPathComponent(DownloadStore.hash("en.test\n/gone/1"))
        try fm.createDirectory(at: orphan, withIntermediateDirectories: true)
        try jpeg.write(to: orphan.appendingPathComponent("001.jpg"))
        try jpeg.write(to: folder.appendingPathComponent(DownloadStore.hash("en.test\n/gone/2") + ".cbz"))
        let partial = folder.appendingPathComponent(DownloadStore.hash(manga.chapter(2).key))
        try fm.createDirectory(at: partial, withIntermediateDirectories: true)
        try Data().write(to: partial.appendingPathComponent(DownloadStore.partialMarker))
        try jpeg.write(to: partial.appendingPathComponent("001.jpg"))

        downloads.reindex()

        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: folder.path)), [DownloadStore.hash(manga.chapter(1).key), DownloadStore.hash(manga.chapter(2).key)])
        XCTAssertTrue(downloads.isDownloaded(manga.chapter(1).key))
        XCTAssertFalse(downloads.isDownloaded(manga.chapter(2).key))
    }

    func testDeleteRemovesFilesAndRow() async throws {
        let repo = try LibraryRepository.inMemory()
        let manga = SourceFixture.manga(in: repo, chapters: 1)
        let downloads = manager(repo, SourceManager(extensions: try SourceFixture.extensions()), transport())
        downloads.enqueue([manga.chapter(1)])
        await downloads.waitUntilIdle()

        downloads.delete([manga.chapter(1)])
        XCTAssertFalse(downloads.isDownloaded(manga.chapter(1).key))
        let pages = await downloads.localPages(manga.chapter(1).key)
        XCTAssertNil(pages)
        XCTAssertEqual(filesOnDisk(), [])
        XCTAssertEqual(try rowCount(repo, state: 1), 0)
        XCTAssertEqual(downloads.downloadedCount(mangaKey: manga.key), 0)
    }

    func testQueueAndPauseSurviveARelaunch() async throws {
        let repo = try LibraryRepository.inMemory()
        let manga = SourceFixture.manga(in: repo, chapters: 3)
        let sources = SourceManager(extensions: try SourceFixture.extensions())
        let first = manager(repo, sources, transport())
        first.pause()
        first.enqueue([manga.chapter(2), manga.chapter(1), manga.chapter(3)])
        first.move(manga.chapter(3).key, to: 1)

        let relaunched = manager(repo, sources, transport())
        XCTAssertTrue(relaunched.isPaused)
        XCTAssertEqual(relaunched.queue.map(\.chapterURL), ["/c/2", "/c/3", "/c/1"])
        XCTAssertEqual(relaunched.queue.map(\.mangaTitle), ["Manga", "Manga", "Manga"])
    }

    func testChangedChapterURLKeepsItsDownloadAndRemovedChapterLosesIt() async throws {
        let repo = try LibraryRepository.inMemory()
        let manga = SourceFixture.manga(in: repo, chapters: 2)
        let downloads = manager(repo, SourceManager(extensions: try SourceFixture.extensions()), transport())
        let one = manga.chapter(1), two = manga.chapter(2)
        downloads.enqueue([one, two])
        await downloads.waitUntilIdle()
        XCTAssertTrue(downloads.isDownloaded(two.key))

        repo.applyChapters([SourceChapter(url: "/n/1", name: "Ch 1", number: 1, date: nil, scanlator: nil)], to: manga)

        let newKey = LibraryManga.makeKey(sourceId: SourceFixture.sourceId, url: "/n/1")
        XCTAssertTrue(downloads.isDownloaded(newKey))
        XCTAssertFalse(downloads.isDownloaded(one.key))
        let pages = await downloads.localPages(newKey)
        XCTAssertEqual(pages?.map(\.lastPathComponent), ["001.jpg", "002.jpg", "003.jpg"])
        let mangaFolder = root.appendingPathComponent(SourceFixture.sourceId).appendingPathComponent(DownloadStore.hash(manga.key))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: mangaFolder.path), [DownloadStore.hash(newKey)])
        XCTAssertFalse(downloads.isDownloaded(two.key))
        XCTAssertEqual(try downloadRows(repo).map { $0["chapterKey"] as String }, [newKey])
    }

    func testDownloadOfADeletedChapterIsNotMarkedDownloaded() async throws {
        let repo = try LibraryRepository.inMemory()
        let manga = SourceFixture.manga(in: repo, chapters: 1)
        let downloads = manager(repo, SourceManager(extensions: try SourceFixture.extensions()), transport())
        downloads.pause()
        downloads.enqueue([manga.chapter(1)])
        repo.write { try $0.execute(sql: "DELETE FROM chapter") }

        downloads.resume()
        await downloads.waitUntilIdle()

        XCTAssertFalse(downloads.isDownloaded(manga.chapter(1).key))
        XCTAssertEqual(filesOnDisk(), [])
    }

    func testCBZChapterIsOneArchiveAndReadsBackItsPages() async throws {
        Pref.saveAsCBZ.set(true, in: defaults)
        let repo = try LibraryRepository.inMemory()
        let manga = SourceFixture.manga(in: repo, chapters: 1)
        let downloads = manager(repo, SourceManager(extensions: try SourceFixture.extensions()), transport())

        downloads.enqueue([manga.chapter(1)])
        await downloads.waitUntilIdle()

        XCTAssertEqual(filesOnDisk().count, 1)
        XCTAssertEqual(filesOnDisk().first.map { ($0 as NSString).pathExtension }, "cbz")
        let local = await downloads.localPages(manga.chapter(1).key)
        let pages = try XCTUnwrap(local)
        XCTAssertEqual(pages.map(\.lastPathComponent), ["001.jpg", "002.jpg", "003.jpg"])
        XCTAssertEqual(try Data(contentsOf: pages[0]), jpeg)
        XCTAssertGreaterThan(downloads.chapterCacheSize(), 0)
    }

    func testCBZChapterUnpacksOffTheMainThread() async throws {
        Pref.saveAsCBZ.set(true, in: defaults)
        let repo = try LibraryRepository.inMemory()
        let manga = SourceFixture.manga(in: repo, chapters: 1)
        let sources = SourceManager(extensions: try SourceFixture.extensions())
        let downloads = manager(repo, sources, transport())
        downloads.enqueue([manga.chapter(1)])
        await downloads.waitUntilIdle()
        downloads.clearChapterCache()
        DownloadStore.lastUnpackOnMainThread = nil

        let pages = try await PageProvider(sources: sources, downloads: downloads).pages(for: manga.chapter(1))

        XCTAssertEqual(pages.count, 3)
        XCTAssertTrue(pages.allSatisfy { if case .local = $0 { true } else { false } })
        XCTAssertEqual(DownloadStore.lastUnpackOnMainThread, false)
    }
}
