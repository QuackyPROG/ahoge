# Audit fixes (GitHub issues #2-#14)

## Problem
A read-only code audit filed 13 bug reports on QuackyPROG/ahoge. Four of them are bugs the user hits every day:

- **#2 Navigation.** A screen opened from Global search, a manga page or More > Migrate lands *underneath* the current screen. The user sees nothing happen, taps Back, and only then sees the screen they asked for. After a migration, Back returns to a migrate search for an entry that is no longer in the library.
- **#3 Push script.** The Windows timer that installs new builds on the phone runs `xtool install` whenever `main` has a new commit (20-50 a day), which kills the running app. To the user this looks like a crash.
- **#4 No state restoration.** When iOS evicts the suspended app, the next launch starts on Library with nothing open.
- **#5 Reader memory.** Reading long webtoons across chapters grows memory without a limit until iOS kills the app.

The other reports (#6-#14) cover data loss and correctness: auto-backup on the main thread and deleting manual backups, a `fatalError` on database open, dropped write errors, chapter URL changes wiping read state, wrong chapters marked read, clear/restore/migrate losing data, iPad layout resets, UI glitches, download races and minor update/import bugs.

## Solution
Fix every item the user accepted in `DECISIONS.md`, one root cause per ticket and one commit per ticket, each with a regression test where a seam exists. The user's own bugs go first. The fixes keep the existing look and add no dependencies.

## User stories
1. As a reader, I want a result tapped in Global search (or a source header, genre, author or migrate title) to open on top of the screen I tapped it on, so that I see what I asked for without pressing Back. (#2)
2. As a reader who migrates a title, I want the new entry's page to replace the old page and the migrate search, or to return to the titles list when I started from More > Migrate, so that Back never leads to an entry that is gone. (#2)
3. As the phone's owner, I want new builds installed only during a quiet window at night (default 02:00-06:00, set with `-QuietHours`), with `--force` for an immediate install and re-signing at any hour when the 7-day signature has less than a day left, so that the app is never killed while I use it and never expires. (#3)
4. As a reader, I want the app to reopen on the tab, manga page and reader chapter and page I left, after iOS evicts it, so that it does not look like a reset. (#4)
5. As a webtoon reader, I want memory to stay bounded however many chapters I read in a row, so that iOS does not kill the app. (#5)
6. As a user, I want automatic backups made without freezing the app when I leave it, and never at the cost of my manual backups. (#6)
7. As a user, I want a database that cannot open to show an error screen with Retry and Share logs instead of crashing, and failed saves to be logged and shown, so that I never lose changes silently; and my extension repositories to survive an unreadable state file. (#7)
8. As a reader, I want a source's chapter URL change to keep my read state, bookmarks, last page, history and downloads, without flooding Updates, and orphaned download files to be cleaned up. (#8)
9. As a reader, I want "Previous chapter" and chapter-list jumps to mark only the chapters I read, and reading time credited to the chapter I am reading. (#9)
10. As a user, I want restore to ask before it runs and to leave my settings alone unless I ask for them, Clear database to keep titles I have started, bookmarked or have history for, destructive data actions to ask first, and restore and migration to keep chapter order, categories, update intervals, progress, history and per-series settings. (#10)
11. As an iPad or Max-phone user, I want the layout and every tab's screens to stay put when the window resizes or I switch sidebar items, and notification taps to open above anything presented. (#11)
12. As a user, I want sheets and covers never blank, every search result and tag shown once, toolbars and panes that fit narrow widths and large text, a search field that resets after a search, and the "Pinned only" toggle to affect only the screen I toggle it on. (#12)
13. As a reader of downloads, I want CBZ chapters to open without freezing the UI, resumed downloads to have exactly the right pages, and cancelled downloads to stay cancelled. (#13)
14. As a user, I want "Never" titles skipped by manual library updates, metadata kept when a source returns empty values, and Mihon backups restored under the right language's source. (#14)

## Implementation decisions

### Process (applies to every ticket)
- **Branch and PR.** All work is on branch `fix/audit` with one **draft** PR to `main`. Neither exists on the remote yet (checked with `git ls-remote` and `gh pr list` on 2026-11-20). Ticket 01's agent pushes the branch and opens the PR with `gh pr create --draft --base main --head fix/audit`. Nobody pushes to `main`, because the phone push script deploys `main`.
- **Commits.** One commit per ticket. The message says why and references its issue: `Fixes #N` when the ticket closes the issue, `Part of #N` when the issue is split across tickets. Only the last ticket of a split issue uses `Fixes #N`.
- **Verification.** Nobody can run Swift on the Windows dev machine. After each commit the build agent pushes `fix/audit`, waits for the `test` job of `.github/workflows/ios.yml` on the draft PR (`gh pr checks --watch` or `gh run watch <run-id>`), and reports the run URL and result. A ticket is done only when that job is green. On a red run the agent reads the failure (`gh run view <id> --log-failed`) and fixes it in the same ticket.
- **One ticket per CI run, sequential.** Tickets run one at a time. After pushing a ticket's commit, the agent waits for that run to go green before starting the next ticket. The workflow cancels an in-progress run when a newer push arrives, so pushing the next ticket early would cancel the previous ticket's run and leave it unverified.
- **Tests.** Every fix gets a regression test in `Tests/AhogeTests` at the seams below. UI-only fixes are verified by the CI simulator build compiling the change. CI has no screenshot step and the project has no UI test target; adding one is a project change the user has not approved, so UI tickets list a manual check for the user instead.
- **Ticket 01 is the exception.** It changes only `Scripts/push-to-phone.sh` and `Scripts/install-push-task.ps1`. It is tested by a new shell-level test run locally with Git Bash on Windows, plus a PowerShell parse check. It still pushes, so the CI run on the PR must stay green.
- No new dependencies. CryptoKit, ImageIO, UIKit and BackgroundTasks are system frameworks already imported by the app.

### Navigation (#2): one value path per tab
- `AppNavigator` (`Ahoge/App/AppNavigator.swift`) owns one `[Route]` path per `AppTab`. Each tab's root view binds its `NavigationStack(path:)` to that path. `LibraryView`'s local `@State path` moves there.
- Every screen that contains value links is pushed as a `Route`. Pushes that are not links (search submit, Open link, context-menu "Extension details", "Search all sources" on a genre, "Migrate") call one `AppNavigator` push method that appends to the selected tab's path.
- All `navigationDestination(item:)` modifiers go (`SourcesView.swift:71-73`, `ExtensionsView.swift:61`, `MangaDetailView.swift:99-100`, `GlobalSearchView.swift:63`).
- New `Route` cases: `.upcoming`, `.migrateSources`, `.migrateTitles(String)` (source id). View-based `NavigationLink { … }` pushes to screens with value links become value links: `MoreView.swift:66`, `MigrateSheet.swift:120`, `SettingsSearch.swift:143` (for the `.migrate` destination), `UpdatesView.swift:131`. View links to settings screens without value links (Appearance, Categories, Data and storage, and so on) stay as they are; the decision only covers screens that contain value links.
- **After a migration** `AppNavigator` rewrites the selected tab's path with one pure rule. When the entry before `.migrate(old)` is `.manga(old)`, both are replaced by `.manga(new)`. Otherwise (started from More > Migrate) `.migrate(old)` is popped, which returns to `.migrateTitles`.
- Verified against Apple's "Understanding the navigation stack" (2026-11-20): "SwiftUI stacks view-based destinations on top of the value-based destinations in the stack's navigation path." That is the cause in #2.

### Reader presentation and state restoration (#4)
- **Prefactor.** The reader is presented from one place. `AppNavigator` holds the open reader (manga and chapter, held strongly), and `RootView` has the only reader `fullScreenCover`. Library, Updates, History and the manga page ask `AppNavigator` to open the reader instead of owning covers (`LibraryView.swift:147`, `UpdatesView.swift:155`, `HistoryView.swift:71`, `MangaDetailView.swift:134`). This lets #4 restore the reader, lets #11 dismiss it before routing, and fixes #12 item 2: the History cover no longer depends on the weak `ChapterRecord.manga` (`LibraryModels.swift:85`).
- **What is saved.** The selected tab, the top-most `.manga` route of that tab's path (its `MangaRef`), and the open reader's manga key, chapter key and current page. Nothing deeper is restored: on launch the tab's path is set to `[.manga(ref)]` only.
- **Where.** In `UserDefaults` through new `Pref` keys, written whenever that state changes. They are left out of `Pref.backupNames`. `@SceneStorage` was rejected: it is not written until the scene backgrounds, so a foreground kill (#5) or a reinstall (#3) would lose it, and the decision asks for restore on every cold launch.
- **Restore.** On a cold launch `AppNavigator` reads the saved state once. The reader reopens at the saved chapter and page (`ReaderModel.open(_:page:provider:)` already takes a page). Missing manga or chapters are skipped quietly.
- **Incognito.** While global incognito is on, or the open title's source is in `Pref.incognitoSources`, only the selected tab is saved. The manga page and the reader position are never saved then. This matches incognito saving no progress or history today (`LibraryRepository.saveProgress`, `LibraryRepository.swift:266`).

### Reader memory (#5): numbers picked
Apple's "Responding to memory warnings" (checked 2026-11-20) says to drop images that can be reloaded and to "restrict the number of simultaneous operations". Apple publishes no byte budgets, so the numbers below follow from bitmap size (width × height × 4 bytes) and the decision's 4096 px cap:
- **Decode cap.** No decoded bitmap is longer than **4096 px** on its longest side. The width cap stays at `ImageLoader.maxPixelWidth` = 2048 px, so the worst-case bitmap is 2048 × 4096 × 4 B = 32 MiB.
- **Tall strips.** In webtoon mode a page taller than 4096 px after width scaling is shown as consecutive **slice items** of at most 4096 px each, built like the existing split-wide halves (`ReaderModel.pageItems`), so the lazy stack keeps only nearby slices. In paged modes the whole page is scaled to fit 4096 px.
- **Decoded image cache** (`ImageMemoryCache.totalCostLimit`, `ImageLoader.swift:11`): 200 MiB → **96 MiB** (three worst-case slices).
- **URLCache memory** (`ImageLoader.swift:36`): 50 MiB → **8 MiB**. The 500 MiB disk cache stays, and decoded pages live in `ImageMemoryCache`.
- **One copy per page.** With a non-identity `ImageTransform` (crop, grayscale, split, rotate), the plain decode is not kept in `ImageMemoryCache` once the transformed copy exists. The size of the untransformed page is still reported for wide-page detection.
- **Prefetch.** At most **2** prefetch decodes run at once. The look-ahead counts stay (5 items, 3 for a new chapter, 1 on cellular with "Preload only on Wi-Fi").
- **Sections.** At most the previous, current and next chapter stay loaded; other sections are dropped as the reader moves on.
- **View state.** `ReaderPageView` releases its decoded image when it leaves the screen and reads the cache again when it comes back.
- **Memory warning.** `UIApplication.didReceiveMemoryWarningNotification` empties `ImageMemoryCache`, purges URLCache memory and cancels pending prefetches.
- The issue's reference `ImageTransform.swift:236-247` is wrong: that file has 67 lines. The second cached copy comes from `ImageLoader.swift:53-58`.

### Reader correctness (#9)
- `loadNext` (`ReaderModel.swift:231-249`) drops its result and its error when `open()` has run since it started. It uses a generation counter, the pattern `SourceBrowseModel` and `GlobalSearch` already use.
- The reading clock stops (crediting the old chapter) at the start of `open()`. The clock restarts when the new chapter is ready, as it does today.

### Push script (#3)
- `push-to-phone.sh` gains `--quiet-hours HH-HH` (start hour inclusive, end hour exclusive, local time; default `02-06`; a window may span midnight, for example `22-06`).
- A new commit is built and installed only inside the window, or at any hour with `--force`. Outside the window the script logs that it is waiting for the window and exits.
- Re-signing the installed build follows the current 3-day rule inside the window. Outside the window it runs only when the signature is 6 days old or more (less than a day before the 7-day expiry). An urgent re-sign outside the window re-signs the installed build; it never installs a new commit.
- The decision logic (in window? install? re-sign?) lives in shell functions that a new `Scripts/test-push-to-phone.sh` calls with fixed hours and ages. The script's side effects (log redirect, `flock`, relay start, `xtool`) do not run under the test.
- `install-push-task.ps1` gains `-QuietHours` (default `'02-06'`), passes it to the script, and adds a daily trigger a few minutes after the window opens next to the `-Minutes` repetition. Without it, the default 6-hour repetition can step over a 4-hour window. **Inferred:** WSL takes the Windows time zone, so `date +%H` in WSL is the PC's local hour. The script logs the hour it used so the user can check.
- The scheduled task does not wake the PC (no `-WakeToRun`). When the PC is off during the window, nothing installs; the log line "waiting for quiet window" shows this, and the user moves the window with `-QuietHours`.

### Auto-backup (#6)
- `AutoBackup.runIfDue` snapshots on the main actor, then encodes, compresses and writes in a detached task inside `UIApplication.beginBackgroundTask(withName:expirationHandler:)`, ending the assertion when done or expired. Apple: `applicationDidEnterBackground` "has five seconds to perform any tasks", and an app that does not end its background tasks "in a timely manner" is terminated (checked 2026-11-20).
- The `app.ahoge.backup` BGTask sets an `expirationHandler` (`BackgroundRefresh.swift:82-90`).
- Automatic backups are named `ahoge_auto_YYYY-MM-DD_HH-mm.ahbk`. Manual exports keep `ahoge_YYYY-MM-DD_HH-mm.ahbk` (`BackupFile.swift:13-20`). Rotation only touches the `ahoge_auto_` names. The decision allowed a name pattern or a subfolder; the name pattern keeps all backups in the folder users already copy from.

### Persistence (#7)
- App start builds its services (library, downloads, updater, background context) in a loader that returns either the services or the database error. On an error, `RootView`'s place shows a full-screen error built from `ErrorStateView` with **Retry** (opens again) and **Share logs** (`AppLog.exportFile()`). Background launches with no services skip work: BGTask handlers already complete with `success: false` when `BackgroundRefresh.context` is nil.
- `LibraryRepository.write` logs failures to `AppLog` and publishes the last failure. `RootView` shows it in one alert in the style of its existing alerts.
- `ExtensionStore.load` tells three cases apart. No `state.json` is a fresh start. A file that cannot be read stays where it is, and saving is blocked for the session. A file that cannot be decoded is renamed aside to `state.json.unreadable-<timestamp>` and saving is blocked for the session. In both failure cases `lastError` says what happened. Keeping an unreadable-but-intact file in place protects a launch before first unlock (**Unknown** whether that happens; the issue marks it unconfirmed).

### Chapter re-keying (#8)
- `ChapterMerge` returns, besides the merged list, the pairs (removed chapter → added chapter) that carry over. Rule: same chapter number ≥ 0. When several removed or added chapters share the number, match by scanlator. When still ambiguous, skip.
- `applyChapters` copies `read`, `bookmark`, `lastPageRead` and `dateFetch` to the added chapter and moves the history row to the new chapter key before deleting the old row. The carried chapters keep the old `dateFetch`, so they are not news in Updates.
- `LibraryUpdater` does not count carried chapters as new (no notification, no "download new chapters").
- The repository tells `DownloadManager` about carried and removed chapters through a callback, like `didMarkRead` (`LibraryRepository.swift:21`, wired at `DownloadManager.swift:105`). Carried downloads move their folder or archive to the new chapter key's location and update the row and index. Removed chapters' downloads are deleted and queued items cancelled. `completed()` does not mark a chapter downloaded when its row cannot be written.
- `reindex` deletes chapter folders and archives that match no chapter row.

### Data screens (#10)
- **Restore** asks first: "Restore library" (default), "Restore library and settings", "Cancel". `BackupService.restore` gets a flag; only the second option writes `Pref.backupNames`. Repositories, sources and titles count as library.
- **Clear database** "keep" rule keeps a title with any chapter that is read, has `lastPageRead > 0` or is bookmarked, or that has history. The toggle text follows the rule.
- **Clear cookies and website data** gets a new destructive confirmation dialog in the style of `ClearDatabaseView.swift:53-60`.
- **Clear database** gets no new dialog: the existing "Remove N titles?" confirmation (`ClearDatabaseView.swift:53-60`) stays. When the keep toggle is off, its message also says that read progress, bookmarks and history are deleted.
- **sourceOrder on restore.** After a restore every chapter of a title has a unique `sourceOrder`. Local chapters keep their relative order. Backup-only chapters with a number ≥ 0 are placed by chapter number among them; the rest go after them in backup order.
- **Category names** are trimmed when matched as well as when created (`LibraryRepository+Backup.swift:136`).
- **Update interval.** The backup's `updateInterval` applies only to titles new to the device, like the other metadata (`LibraryRepository+Backup.swift:67-75`). On an existing title `nil` means Smart, which the user may have chosen.
- **Migration** also carries `lastPageRead` and history under the "Chapters" option. History rows are copied to the matched new chapters (newer date and longer time kept); the old entry's rows are not deleted.
- **Per-series settings.** The reading mode (`reader.mode\n<key>`), orientation (`reader.orientation\n<key>`) and chapter display (`ChapterDisplay` key) of a title go into `BackupManga` as optional fields. They are restored onto titles that have none. Migration copies them to the new entry every time, replacing its values, as Mihon's `MigrateMangaUseCase.kt` does with `chapterFlags` and `viewerFlags` (verified 2026-11-20). Adding optional fields keeps backup format version 1 readable both ways (`Codable` ignores unknown keys; `backup-v1.json` still decodes). One helper next to `PerSeriesReaderSettings` (`ReaderSettings.swift:248-256`) reads, writes, copies and removes a title's keys.
- **Clear database cleanup** removes the cleared titles' per-series keys, and their custom cover files when no remaining row uses the file (the shared-file count in `LibraryRepository+Covers.swift:24`).

### iPad and routing (#11)
- The split view or tab layout is chosen by `UIDevice.current.userInterfaceIdiom`: split view on iPad, tabs on iPhone. Size-class changes no longer rebuild the tree. `MangaDetailView`'s two-pane layout still follows size class.
- On iPad all five tab screens stay alive in the detail column and only the selected one is shown. `UpdatesView`'s last-seen stamp and `HistoryView`'s reload run when the tab is selected (`navigator.tab` changes), not on appear.
- `AppNavigator.open(_:)` dismisses the reader and every open sheet, then appends the route on top of the Library tab's current path (no longer `path = [route]`, `LibraryView.swift:156`). Sheets clear through one shared modifier that observes a dismiss request from `AppNavigator`.

### UI (#12)
1. The migrate sheet (`GlobalSearchView.swift:58-62`) is presented with an item that already holds the old entry, so it is never blank. When the entry is gone at tap time, no sheet opens and the screen says the title is no longer in the library.
2. History's blank cover: fixed by the reader prefactor (ticket 08).
3. Global search results are de-duplicated by URL per source in `GlobalSearch` (`GlobalSearch.swift:93-97`).
4. `SourceBrowseModel` also de-duplicates within one page (`SourceBrowseView.swift:87-88`).
5. Lists of strings that can repeat use the index (or a de-duplicated list) as the `ForEach` id: genres (`MangaDetailView.swift:292`), description images (`MangaDescription.swift:82`), filter options (`FilterSheet.swift:61,149`), preference options (`SourcePreferencesView.swift:73`).
6. The Browse segmented picker loses its fixed `.frame(width: 240)` (`BrowseView.swift:28`) and fits between the toolbar buttons on a 375 pt phone and at large Dynamic Type.
7. The manga page's details pane is no longer a fixed 400 pt (`MangaDetailView.swift:65`); the chapter list keeps a usable width in narrow regular widths.
8. Submitting a search in Sources clears `globalQuery` and ends the search field's active state (`SourcesView.swift:66-70`).
9. "Pinned only" (`GlobalSearchView.swift:21,56`) is per screen: a screen starts from the saved preference, and toggling it saves the preference and re-runs only that screen's search.

### Downloads (#13)
1. Opening a CBZ download unpacks it off the main actor: `PageProvider.pages(for:)` awaits a detached unpack. `DownloadStore` is already `Sendable`.
2. A resumed chapter keeps saved pages only when they were saved for the same page list (a small manifest in the chapter folder), and `finish` keeps exactly one file per page index below the page count.
3. `cancel` during zipping leaves no folder and no `.cbz`: the zipping step checks for cancellation before it moves the archive in place and removes its output when cancelled.
4. Background transport races (`BackgroundTransport.swift:34-45`, `:68-75`) are fixed only if a test shows the race. Otherwise the ticket comments on #13 and #13 stays open.

### Minor (#14)
1. `UpdatePolicy` gives interval 0 its own skip reason that manual updates do not override (`UpdatePolicy.swift:39`, `LibraryUpdater.swift:41`).
2. Metadata refresh (`LibraryRepository.swift:189-193`) keeps the stored author, artist, summary, genres and status when the source returns an empty string, an empty list or status `unknown` (the default `MangaDetails` decodes to when the field is missing, `SourceModels.swift:44`).
3. The Mihon importer picks, among Ahoge sources with the backup source's name, the one whose language reproduces the backup's source id with Mihon's `generateId`: the first 8 bytes of MD5 of `"${name.lowercase()}/$lang/$versionId"` (versionId 1), sign bit cleared (verified in mihonapp/mihon `HttpSource.kt`, 2026-11-20). MD5 comes from CryptoKit's `Insecure.MD5`. Without a match the current rule (English first) stays.

## Reuse first
- Navigation: `AppNavigator` and `AppTab` (`Ahoge/App/AppNavigator.swift`), `Route` and `RouteView` (`Ahoge/App/Route.swift`), the path pattern in `LibraryView` (`Ahoge/Features/Library/LibraryView.swift:24,82,151-157`), `UpdateNotifier.handleTap` (`Ahoge/Library/UpdateNotifier.swift:75-85`), `DeepLinkResolver` (`Ahoge/App/DeepLink.swift`).
- Reader: `ReaderModel` (`Ahoge/Features/Reader/ReaderModel.swift`) with its split-wide item building (`pageItems`, `learnSize`), `PageProvider` (`Ahoge/Downloads/PageProvider.swift`), `ImageLoader` and `ImageMemoryCache` (`Ahoge/Services/ImageLoader.swift`), `PageGeometry` (`Ahoge/Features/Reader/PageGeometry.swift`), the generation-token pattern in `SourceBrowseModel` (`Ahoge/Features/Browse/SourceBrowseView.swift:82-93`).
- Data: `LibraryRepository` and its extensions (`Ahoge/Library/LibraryRepository*.swift`), `ChapterMerge` (`Ahoge/Library/ChapterMerge.swift`), `BackupService`, `BackupCodec`, `BackupFile`, `BackupPreferences`, `AutoBackup`, `BackupSchedule` (`Ahoge/Backup/`), `MigrateOptions` (`Ahoge/Library/LibraryRepository+Migrate.swift`), `PerSeriesReaderSettings` (`Ahoge/Features/Reader/ReaderSettings.swift:248`), `ChapterDisplay.load/save` (`Ahoge/Features/Manga/ChapterDisplay.swift:92-104`), `CoverStore` (`Ahoge/Library/CoverStore.swift`).
- Downloads: `DownloadManager`, `DownloadStore`, `BackgroundTransport` (`Ahoge/Downloads/`), `ZipArchive` (`Ahoge/Services/ZipArchive.swift`).
- App shell: `AhogeApp` (`Ahoge/App/AhogeApp.swift`), `RootView` and its alerts (`Ahoge/App/RootView.swift`), `BackgroundRefresh` (`Ahoge/Library/BackgroundRefresh.swift`), `AppLog.exportFile()` (`Ahoge/Services/AppLog.swift`), `ErrorStateView` (`Ahoge/Features/Shared/ErrorStateView.swift`), `Pref` keys (`Ahoge/App/Preferences.swift`).
- Tests: `LibraryRepository.inMemory()`, `SourceFixture` (`Tests/AhogeTests/Support/SourceFixture.swift`), `StubTransport` (`Tests/AhogeTests/Support/StubTransport.swift`), isolated `UserDefaults(suiteName:)` as in `EntryScreenTests.swift:10-14`, `ProtoWriter` for Mihon backups.
- Scripts: `Scripts/push-to-phone.sh`, `Scripts/install-push-task.ps1`.

## Seams
- **`AppNavigator` (unit, new `Tests/AhogeTests/AppNavigatorTests.swift`).** Catches: pushes land on the selected tab's path; the migration path rewrite; `open(_:)` appending on top of Library and raising the dismiss request; reader open and close; save and restore of tab, manga and reader. Misses: whether SwiftUI renders the stack as the path says. That is covered by removing every `navigationDestination(item:)` and view link to value-link screens (checked by grep in the tickets) and by a manual check for the user.
- **`ReaderModel` with `PageProvider` (unit, `ReaderModelTests.swift`).** Catches: stale `loadNext`, the section window, slice items, the clock on `open()`. `PageProvider`'s remote page lookup becomes injectable so a test can hold a chapter's pages until after `open()`. This is a new seam with two adapters: the source lookup and a test gate. Misses: scroll behaviour on screen.
- **`ImageLoader.decode` and `ImageMemoryCache` (unit, `ImageLoaderTests.swift`).** Catches: 4096 px cap, slice decoding, cache limit, one copy per transformed page, purge on a posted memory-warning notification. Misses: real jetsam limits on a device.
- **`LibraryRepository` on `inMemory()` (unit).** Catches: re-key carry-over, history moves, clear-database rule and cleanup, restore order, trim, interval, migration progress and history, metadata blanking, write-failure reporting. Misses: on-disk SQLite I/O errors.
- **`DownloadManager` with `StubTransport` and temp folders (unit, `DownloadManagerTests.swift`).** Catches: re-link and cleanup of re-keyed or removed chapters, orphan sweep, resume manifest, cancel during zip, off-main CBZ unpack. Misses: the background `URLSession`.
- **`BackupService` / `AutoBackup` with isolated defaults and a temp folder (unit).** Catches: restore with or without settings, per-series settings round trip, auto names and rotation. The backup folder becomes a parameter so tests do not write into Documents. Misses: the real background-time limit.
- **`ExtensionStore(directory:)` (unit, `ExtensionStoreTests.swift`).** Catches: unreadable and undecodable `state.json` handling.
- **`UpdatePolicy` and `MihonBackupImporter` (unit, existing tests).** Catch: the Never rule and the language match.
- **Shell (`Scripts/test-push-to-phone.sh`, run locally in Git Bash).** Catches: window membership including midnight wrap, install and re-sign decisions by hour and signature age, `--force`. A PowerShell parser check catches syntax errors in `install-push-task.ps1`. Misses: `xtool` and the Windows scheduler, which the user checks on the PC.
- **CI simulator build only.** Layout fixes (#12 items 6-7), the iPad layout (#11), the error screen (#7). These have no automated check beyond compiling; each ticket lists a manual check for the user.

## Out of scope
- #13 item 4 when no test can show the race (the ticket leaves a comment on #13 and the issue stays open).
- #14 item 4 (JS runtime off the main thread) and item 5 (library load off the main thread at launch). They stay open in #14, so every #14 ticket uses `Part of #14`.
- Restoring anything deeper than the tab, one manga page and the reader.
- A UI test target or screenshot step in CI.
- Changing the push script's build steps, device discovery or ancestry check, or adding WakeToRun to the scheduled task (declined, `DECISIONS.md` Round 2).
- Rotating automatic backups written before this change. They have the manual name pattern and cannot be told apart.
- Moving the settings screens without value links (Appearance, Categories and others) to `Route`.

## Open questions
None. All three questions were resolved in `DECISIONS.md`, Round 2 (2026-11-20):
1. **Clear database confirmation (#10).** Resolved: no new dialog. When the keep toggle is off, the existing "Remove N titles?" message also says read progress, bookmarks and history are deleted. Clear cookies gets a new confirmation. See "Data screens" and ticket 31.
2. **Incognito and state restoration (#4).** Resolved: only the selected tab is saved, never the manga page or reader position. See "Reader presentation and state restoration" and ticket 09.
3. **PC asleep in the quiet window (#3).** Resolved: the task does not wake the PC. The script logs that it is waiting for the window, and `-QuietHours` moves the window. See "Push script" and ticket 01.
