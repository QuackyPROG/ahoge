import Foundation

@main struct MihonDomainRegression {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message) }
    static func rejects(_ body: () throws -> Void, _ message: String) { do { try body(); fatalError(message) } catch {} }
    static func manga(_ id: String, source: String) -> Manga { Manga(id: id, sourceID: source, title: id, author: "", summary: "", genres: [], coverHexes: [], coverURL: nil, statusText: "") }
    static func chapter(_ id: String, manga: String, number: Double) -> Chapter { Chapter(id: id, mangaID: manga, title: id, number: number, releaseDate: .distantPast, isDownloaded: false, pages: []) }

    @MainActor static func main() async throws {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let old = try decoder.decode(LibraryEntry.self, from: Data(#"{"mangaID":"a","categoryID":"old","addedAt":"2020-01-01T00:00:00Z"}"#.utf8))
        expect(old.categoryIDs == ["old"], "Legacy single membership")
        let multi = LibraryEntry(mangaID: "a", categoryID: "old", addedAt: .distantPast, categoryIDs: ["old", "other"])
        let multiDecoded = try decoder.decode(LibraryEntry.self, from: encoder.encode(multi))
        expect(multiDecoded == multi, "Multi category round-trip")
        let oldState = try decoder.decode(PersistedState.self, from: Data(#"{"schemaVersion":6}"#.utf8))
        expect(oldState.chapterStates.isEmpty && oldState.knownChapters.isEmpty && oldState.readerPreferences.parity == .default, "Missing new fields default")
        rejects({ _ = try decoder.decode(PersistedState.self, from: Data(#"{"schemaVersion":999}"#.utf8)) }, "Future snapshot must fail")
        var state = oldState
        state.chapterStates["ch"] = ChapterState(mangaID: "a", chapterID: "ch", isRead: true, isBookmarked: true)
        state.updatesSeenChapterIDs = ["different"]
        let roundtrip = try decoder.decode(PersistedState.self, from: encoder.encode(state))
        expect(roundtrip.chapterStates["ch"]?.isRead == true && !roundtrip.updatesSeenChapterIDs.contains("ch"), "Read and update-seen remain independent")
        let original = manga("a", source: "one"), target = manga("b", source: "two")
        let originalChapters = [chapter("a0", manga: "a", number: 0), chapter("a1", manga: "a", number: 1), chapter("a2", manga: "a", number: 2)]
        let targets = [chapter("b0", manga: "b", number: 0), chapter("b1", manga: "b", number: 1), chapter("bx", manga: "b", number: 1)]
        let plan = try MigrationPlan.build(original: original, target: target, originalChapters: originalChapters, targetChapters: targets)
        expect(plan.chapterMap == ["a0": "b0"] && plan.unmappedCount == 2, "Prologue exact match, duplicate numbers and missing numbers unmapped")
        rejects({ _ = try MigrationPlan.build(original: original, target: target, originalChapters: originalChapters, targetChapters: [targets[0], targets[0]]) }, "Duplicate target identities")
        rejects({ _ = try MigrationPlan.build(original: original, target: target, originalChapters: originalChapters, targetChapters: [chapter("wrong", manga: "a", number: 0)]) }, "Chapter ownership")
        var migrationState = PersistedState.default
        migrationState.library = [LibraryEntry(mangaID: "a", categoryID: "", addedAt: .distantPast), LibraryEntry(mangaID: "b", categoryID: "", addedAt: .distantPast)]
        migrationState.chapterStates["a0"] = ChapterState(mangaID: "a", chapterID: "a0", isRead: true, isBookmarked: true)
        migrationState.chapterStates["b0"] = ChapterState(mangaID: "b", chapterID: "b0", pageIndex: 5, totalPages: 20)
        let transferred = try MigrationStateTransfer.apply(state: migrationState, plan: plan, options: MigrationOptions())
        expect(transferred.library.count == 2 && transferred.chapterStates["b0"]?.isRead == true && transferred.chapterStates["b0"]?.pageIndex == 5, "Duplicate target merges flags without erasing target progress")
        migrationState.securityPreferences.lockLibraryEdits = true
        rejects({ _ = try MigrationStateTransfer.apply(state: migrationState, plan: plan, options: MigrationOptions()) }, "Migration edit lock")
        expect(PackageVersion.newer("1.2.0", than: "1.1.9"), "Semver update")
        expect(!PackageVersion.newer("garbage", than: "1"), "Unknown version is not invented update")
        expect(!PackageVersion.newer("1.2-beta", than: "1.1"), "Unknown prerelease comparison is conservative")
        let collection = BackupCollection(categories: [], entries: [LibraryEntry(mangaID: "a", categoryID: "", addedAt: .distantPast)], mangas: [original], chapters: ["a": originalChapters], progress: [], chapterStates: [:], seen: [])
        let backup = AhogeBackup(createdAt: .distantPast, appVersion: "test", sections: [.library], collection: collection)
        let data = try backup.encoded()
        let decodedBackup = try AhogeBackup.decode(data)
        expect(decodedBackup == backup, "Selected library backup round-trip")
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        expect(json["preferences"] == nil && json["history"] == nil && json["repositories"] == nil, "Unselected sections are absent")
        var invalid = backup; invalid.schemaVersion = 999
        rejects({ try invalid.validate() }, "Future backup")
        invalid = backup; invalid.collection?.entries.append(collection.entries[0])
        rejects({ try invalid.validate() }, "Duplicate library identities")
        invalid = backup; invalid.collection?.progress = [ReadingProgress(mangaID: "a", chapterID: "missing", chapterTitle: nil, pageIndex: 0, totalPages: 0, updatedAt: .distantPast)]
        rejects({ try invalid.validate() }, "Dangling progress reference")
        invalid = backup; invalid.sections.insert(.history)
        rejects({ try invalid.validate() }, "Selection/content mismatch")
        rejects({ _ = try AhogeBackup.decode(Data("{broken".utf8)) }, "Malformed JSON")
        rejects({ _ = try AhogeBackup.decode(Data(#"{"schemaVersion":1,"schemaVersion":2}"#.utf8)) }, "Duplicate object keys")
        rejects({ _ = try AhogeBackup.decode(Data(#"{"collection":{"chapters":{"a":[],"a":[]}}}"#.utf8)) }, "Nested duplicate keys")
        try BackupJSONValidation.validate(Data(#"{"escaped\"key":[],"different":{}}"#.utf8))
        // F-006: unselected records keep their durable, cold-launch references.
        var retainedState = PersistedState.default
        let historyTitle = manga("history-only", source: "one")
        let trackingTitle = manga("tracking-only", source: "one")
        let noteTitle = manga("notes-only", source: "one")
        retainedState.persistedMangas = [historyTitle, trackingTitle, noteTitle]
        retainedState.knownChapters = [historyTitle.id: [chapter("hc", manga: historyTitle.id, number: 1)]]
        retainedState.history = [HistoryEntry(id: UUID(), mangaID: historyTitle.id, chapterID: "hc", pageIndex: 3, timestamp: .distantPast)]
        retainedState.trackers = [TrackerBinding(id: UUID(), mangaID: trackingTitle.id, service: .anilist, remoteTitle: "Local", status: "Reading", progressText: "0", score: "")]
        retainedState.mangaNotes = [noteTitle.id: "Keep this note"]
        let restored = try BackupRestorePlan.apply(backup, to: retainedState)
        let cold = try decoder.decode(PersistedState.self, from: encoder.encode(restored))
        try BackupRestorePlan.validateReferences(cold)
        expect(cold.library == collection.entries && cold.history == retainedState.history && cold.trackers == retainedState.trackers && cold.mangaNotes == retainedState.mangaNotes, "Library-only restore preserves unselected records")
        expect(cold.persistedMangas.contains(historyTitle) && cold.persistedMangas.contains(trackingTitle) && cold.persistedMangas.contains(noteTitle) && cold.knownChapters[historyTitle.id]?.first?.id == "hc", "Cold launch resolves history/tracking/notes-only metadata")
        var overlap = PersistedState.default
        overlap.persistedMangas = [original]; overlap.library = collection.entries
        overlap.knownChapters = ["a": originalChapters]
        overlap.chapterStates["a1"] = ChapterState(mangaID: "a", chapterID: "a1", isRead: true, isBookmarked: true)
        let supportChapter = chapter("history-new", manga: "a", number: 4)
        let incomingHistory = HistoryEntry(id: UUID(), mangaID: "a", chapterID: supportChapter.id, pageIndex: 0, timestamp: .distantPast)
        let historyBackup = AhogeBackup(createdAt: .distantPast, appVersion: "test", sections: [.history], history: [incomingHistory],
            supportingMangas: [original], supportingChapters: ["a": [chapter("a1", manga: "a", number: 99), supportChapter]])
        let overlapResult = try BackupRestorePlan.apply(historyBackup, to: overlap)
        expect(overlapResult.knownChapters["a"]?.contains(originalChapters[1]) == true && overlapResult.knownChapters["a"]?.contains(supportChapter) == true && overlapResult.chapterStates == overlap.chapterStates, "History-only restore merges without replacing collection chapters")
        let overlapCold = try decoder.decode(PersistedState.self, from: encoder.encode(overlapResult))
        try BackupRestorePlan.validateReferences(overlapCold)
        var dangling = retainedState; dangling.knownChapters = [:]
        rejects({ _ = try BackupRestorePlan.apply(backup, to: dangling) }, "Reject proposed dangling retained reference before commit")
        expect(dangling.history == retainedState.history && dangling.persistedMangas == retainedState.persistedMangas, "Rejected restore preserves original model")

        // F-007: transport/malformed failures, persistence, admission and retry.
        let definition = ImportedSourceDescriptor(id: "def", sourceID: "remote", name: "Remote", language: .multi,
            languageCode: "all", baseURL: "https://example.org", packageName: "p", version: "1.0",
            allowsAdultContent: false, apkURL: nil, engineFamily: .api, supportStatus: .live,
            capabilities: [], featureFlags: [], overrides: [:], origin: "test", summary: "test")
        func package(_ id: String, _ version: String) -> SourceRepoPackage {
            SourceRepoPackage(id: id, name: id, packageName: id, apkURL: nil, languageCode: "all", version: version,
                allowsAdultContent: false, sources: [definition])
        }
        let installedPackage = package("installed", "1.0")
        let goodRecord = SourceRepoRecord(id: "repo", url: "https://example.org/index.json", title: "Known title", fetchedAt: .distantPast,
            packages: [package("installed", "2.0"), package("available", "1.0")], importedSources: [definition], lastError: nil)
        var installations = ["repo::installed": PackageInstallation(package: installedPackage, trusted: true, enabled: true)]
        var fetchedURLs: [String] = []
        for failure in [URLError(.notConnectedToInternet) as Error, SourceRepoImportError.invalidPayload as Error] {
            let failed = await RepositoryRefreshPolicy.refresh(goodRecord) { url in fetchedURLs.append(url); throw failure }
            let relaunched = try decoder.decode(SourceRepoRecord.self, from: encoder.encode(failed))
            expect(relaunched.id == goodRecord.id && relaunched.url == goodRecord.url && relaunched.title == goodRecord.title && relaunched.fetchedAt == goodRecord.fetchedAt && relaunched.packages == goodRecord.packages && relaunched.importedSources == goodRecord.importedSources && relaunched.lastError != nil, "Refresh failures preserve entire last-good catalog after relaunch")
            let installedCold = try decoder.decode([String: PackageInstallation].self, from: encoder.encode(installations))
            expect(PackageAdmission.records([relaunched], installations: installedCold).first?.packages == [installedPackage], "Refresh failure keeps installed runtime version separate from available update")
            expect(relaunched.packages.map(\.id) == ["installed", "available"] && PackageVersion.newer(relaunched.packages[0].version, than: installedPackage.version), "Installed and available catalog management remain reachable")
            installations["repo::installed"]?.enabled = false
            expect(PackageAdmission.records([relaunched], installations: installations).first?.packages.isEmpty == true, "Disable remains effective after failed refresh")
            installations.removeValue(forKey: "repo::installed")
            expect(PackageAdmission.records([relaunched], installations: installations).first?.packages.isEmpty == true && relaunched.packages.count == 2, "Uninstall retains fetched available definitions")
            installations["repo::installed"] = PackageInstallation(package: installedPackage, trusted: true, enabled: true)
            let retried = await RepositoryRefreshPolicy.refresh(relaunched) { _ in goodRecord }
            expect(retried == goodRecord && retried.lastError == nil, "Successful retry replaces error with successful catalog")
        }
        expect(fetchedURLs == [goodRecord.url, goodRecord.url], "Refresh requests use original endpoint")

        // F-008: deterministic request spy records exactly the descriptor/cursor used.
        var feed = SourceFeedSession()
        var requests: [SourceFeedSession.Request] = []
        let descriptorA = SourceFeedDescriptor(sourceID: "one", mode: .search, query: "A", filters: [.sort("popular")])
        let descriptorB = SourceFeedDescriptor(sourceID: "one", mode: .search, query: "B", filters: [.sort("popular")])
        let firstA = feed.begin(descriptorA); requests.append(firstA)
        feed.finish(firstA, addedCount: 2)
        feed.invalidate() // Editing the query clears the feed, before B is submitted.
        expect(feed.nextRequest() == nil && feed.page == 0 && !feed.reachedEnd, "Query edit then load more cannot mix results or skip page one")
        let firstB = feed.begin(descriptorB); requests.append(firstB)
        expect(firstB.page == 1 && !feed.accepts(firstA), "New submission rejects late previous response")
        let filteredB = SourceFeedDescriptor(sourceID: "one", mode: .search, query: "B", filters: [.sort("title")])
        let filteredFirst = feed.begin(filteredB); requests.append(filteredFirst)
        expect(!feed.accepts(firstB) && feed.page == 0 && !feed.reachedEnd, "Filter change during request invalidates and resets")
        feed.finish(firstB, addedCount: 10)
        expect(feed.page == 0 && feed.isLoading, "Late old filter response cannot publish or end current loading")
        feed.finish(filteredFirst, addedCount: 2)
        let next = feed.nextRequest()!; requests.append(next)
        expect(next.page == 2 && next.descriptor == filteredB, "Append uses immutable submitted descriptor")
        feed.fail(next)
        let retry = feed.nextRequest()!; requests.append(retry)
        expect(retry.page == 2 && retry.descriptor == next.descriptor, "Retry keeps failed cursor and descriptor")
        feed.finish(retry, addedCount: 0)
        expect(feed.nextRequest() == nil && feed.reachedEnd, "Empty append stops unchanged feed")
        expect(requests.map(\.page) == [1, 1, 1, 2, 2] && requests.map { $0.descriptor.query } == ["A", "B", "B", "B", "B"], "Request spy observes page-one resets and unchanged append/retry")

        // F-009: the production dispatcher uses this same operation/capability policy.
        let allFilters: [SourceFilterValue] = [.sort("title"), .orderAscending(true), .types(["manhwa"]), .genreInclude(mode: "OR", slugs: ["action"]), .genreExclude(mode: "OR", slugs: ["horror"])]
        let natsuFilters = SourceSearchFilters.supported(family: .natsuId, adapter: nil, query: "hero")
        for mode in [SourceFeedKind.popular, .latest] {
            let operation = SourceFeedOperation.make(mode: mode, query: "ignored", filters: allFilters, page: 2, supported: natsuFilters)
            expect(operation == (mode == .popular ? .popular(page: 2) : .latest(page: 2)), "Popular/Latest dispatch cannot claim search filters")
        }
        var filteredSession = SourceFeedSession()
        let submitted = SourceFeedDescriptor(sourceID: "natsu", mode: .search, query: "hero", filters: allFilters)
        let searchFirst = filteredSession.begin(submitted)
        filteredSession.finish(searchFirst, addedCount: 2)
        let searchAppend = filteredSession.nextRequest()!
        filteredSession.fail(searchAppend)
        let searchRetry = filteredSession.nextRequest()!
        let operations = [searchFirst, searchAppend, searchRetry].map { request in
            SourceFeedOperation.make(mode: request.descriptor.mode, query: request.descriptor.query,
                filters: request.descriptor.filters, page: request.page, supported: natsuFilters)
        }
        expect(operations == [1, 2, 2].map { SourceFeedOperation.search(SourceSearchRequest(query: "hero", page: $0, filters: allFilters)) }, "Search dispatch forwards supported filters on first/append/retry")
        let dexFilters = SourceSearchFilters.supported(family: .api, adapter: "mangadex", query: "hero")
        expect(!dexFilters.ascending && !dexFilters.types && dexFilters.includeGenres && dexFilters.excludeGenres, "MangaDex hides ignored ascending/type controls")
        expect(dexFilters.applying(allFilters) == [allFilters[0], allFilters[3], allFilters[4]], "MangaDex dispatch drops unsupported kinds")
        expect(dexFilters.applying([.sort("popular")]).isEmpty && dexFilters.sorts.contains("followedCount"), "MangaDex uses engine order keys instead of generic sort names")
        let themesiaFilters = SourceSearchFilters.supported(family: .mangaThemesia, adapter: nil, query: "hero")
        expect(themesiaFilters.applying(allFilters).isEmpty && themesiaFilters.sorts == ["popular", "update"], "Themesia exposes only consumed ordering")
        for adapter in ["ezmanhwa", "unknown"] {
            expect(!SourceSearchFilters.supported(family: .api, adapter: adapter, query: "hero").isAvailable, "Text-search filters are gated when the engine ignores them")
        }
        expect(!SourceSearchFilters.supported(family: .madara, adapter: nil, query: "hero").isAvailable, "Madara ignores search filters and has no editable controls")
        let weebFilters = SourceSearchFilters.supported(family: .api, adapter: "weebcentral", query: "hero")
        expect(weebFilters.ascending && weebFilters.types && weebFilters.includeGenres && weebFilters.excludeGenres && weebFilters.sorts.contains("Best Match"), "WeebCentral exposes its compiled parameter capabilities")
        let heanFilters = SourceSearchFilters.supported(family: .api, adapter: "heancms", query: "hero")
        expect(heanFilters.sorts == ["total_views", "latest"] && heanFilters.ascending && !heanFilters.types && !heanFilters.includeGenres, "Hean uses engine ordering keys and gates ignored kinds")
        // F-010: production runtime and policy share the exact URL classifier.
        let baseURL = "https://natsu.example"
        let directQueries = ["https://natsu.example/manga/hero", "  https://natsu.example/manga/hero/  ",
            "http://natsu.example:8080/manga/hero/chapter?x=1#top", "//natsu.example/manga/hero"]
        for query in directQueries {
            expect(NatsuSearchQuery.deepLinkSlug(from: query, baseURL: baseURL) == "hero", "Same-host Natsu manga paths share runtime classification")
            let policy = SourceSearchFilters.supported(family: .natsuId, adapter: nil, query: query, baseURL: baseURL)
            expect(!policy.isAvailable && !policy.allowsPagination && policy.applying(allFilters).isEmpty, "Direct lookup hides all ignored filter kinds and pagination")
            expect(SourceFeedOperation.make(mode: .search, query: query, filters: allFilters, page: 9, supported: policy) == .search(SourceSearchRequest(query: query, page: 1, filters: [])), "Direct lookup dispatch cannot send filters or a later page")
            var direct = SourceFeedSession()
            let lookup = SourceFeedDescriptor(sourceID: "natsu", mode: .search, query: query, filters: policy.applying(allFilters), allowsPagination: policy.allowsPagination)
            let failed = direct.begin(lookup)
            direct.fail(failed)
            expect(direct.page == 0 && direct.nextRequest() == nil, "Failed direct lookup cannot retry a later page")
            let retried = direct.begin(lookup)
            expect(retried.page == 1 && !direct.accepts(failed), "Direct lookup retry starts page one and rejects stale success")
            direct.finish(failed, addedCount: 1)
            expect(direct.isLoading && direct.page == 0, "Stale direct lookup cannot mutate current cursor")
            direct.finish(retried, addedCount: 1)
            expect(direct.reachedEnd && direct.nextRequest() == nil, "Successful nonempty direct lookup has no Load more")
            let empty = direct.begin(lookup)
            direct.finish(empty, addedCount: 0)
            expect(direct.reachedEnd && direct.nextRequest() == nil, "Empty direct lookup is exhausted")
        }
        for query in ["hero", "natsu::12::hero", "", "  ", "/manga/hero", "https://other.example/manga/hero",
            "https://sub.natsu.example/manga/hero", "https://natsu.example.evil/manga/hero",
            "https://natsu.example/manga", "https://natsu.example/Manga/hero", "https://natsu.example/series/hero"] {
            expect(NatsuSearchQuery.deepLinkSlug(from: query, baseURL: baseURL) == nil, "Nonmatching host/path and ID remain ordinary Natsu search")
            let policy = SourceSearchFilters.supported(family: .natsuId, adapter: nil, query: query, baseURL: baseURL)
            expect(policy.isAvailable && policy.allowsPagination && policy.applying(allFilters) == allFilters, "Ordinary and blank Natsu search retain advanced filters and pagination")
        }
        for family in [SourceEngineFamily.madara, .mangaBox, .mangaThemesia, .asuraScans] {
            expect(SourceSearchFilters.supported(family: family, adapter: nil, query: "  ", baseURL: baseURL).allowsPagination, "Blank-query runtime branches retain real paginated feeds")
        }
        for adapter in ["mangadex", "heancms", "weebcentral", "ezmanhwa"] {
            for query in ["", "hero", directQueries[0]] {
                expect(SourceSearchFilters.supported(family: .api, adapter: adapter, query: query, baseURL: baseURL).allowsPagination, "Other adapters do not misclassify URLs as direct lookups")
            }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = directory.appendingPathComponent("state.json")
        try AtomicSnapshotWriter.write(Data("original".utf8), to: snapshot)
        rejects({ try AtomicSnapshotWriter.write(Data("replacement".utf8), to: directory.appendingPathComponent("missing/state.json")) }, "Write failure must throw")
        let retained = try Data(contentsOf: snapshot)
        expect(retained == Data("original".utf8), "Previous state survives failure")
        var generation = SearchGeneration()
        let stale = generation.token
        expect(generation.accepts(stale), "Current incremental source results accepted")
        generation.invalidate()
        expect(!generation.accepts(stale), "Cancelled/changed query rejects late partial results")
        expect(generation.accepts(generation.token), "New query remains valid after old-source failure")
        let queue = DownloadQueueCoordinator()
        let job = DownloadJob(id: UUID(), mangaID: "a", chapterID: "a1", sourceID: "one", queuedAt: .now, manga: original, chapter: originalChapters[1], progress: 0, state: .queued, errorMessage: nil)
        expect(queue.startIfIdle(jobs: [job]) { _ in } == job.id, "Queue starts")
        expect(queue.cancelIfActive(jobID: job.id), "Pause cancels active transport")
        expect(queue.activeJobID == job.id, "Cancellation retains directory ownership until unwind")
        expect(queue.startIfIdle(jobs: [job]) { _ in } == nil, "No overlapping replacement transport")
        expect(!queue.finishIfActive(jobID: UUID()), "Stale completion ignored")
        expect(queue.finishIfActive(jobID: job.id) && queue.activeJobID == nil, "Owner completion releases queue")
        print("PASS: compatibility, read/seen, migration identity/mapping, backup negatives/selection/atomic failure, semver, restore references, last-good catalog, captured feed requests and queue ownership regressions")
    }
}
