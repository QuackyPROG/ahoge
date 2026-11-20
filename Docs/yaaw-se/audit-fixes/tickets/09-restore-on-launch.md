# 09: Restore the tab, manga page and reader on a cold launch

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 02, 08
**Issue:** Fixes #4

## What to build
After iOS evicts the app (or after any cold launch), Ahoge reopens on the tab the user left, with the manga page that was open on that tab, and the reader at the same chapter and page if it was open. Nothing deeper is restored.

- `AppNavigator` keeps a small `Codable` snapshot: selected `AppTab`, the top-most `.manga(MangaRef)` of that tab's path (nil when none), and the reader's manga key, chapter key and current page (nil when closed). `MangaRef` and `AppTab` become `Codable` for this.
- The snapshot is written to `UserDefaults` under a new `Pref` key whenever the tab, that path or the reader changes. The reader's current page comes from `ReaderModel.currentPage`; `ReaderView` reports page changes to the navigator. The key is not added to `Pref.backupNames` (`Ahoge/Backup/BackupPreferences.swift`).
- On a cold launch (`AppNavigator` set up by the app, once), the snapshot is read: the tab is selected; its path becomes `[.manga(ref)]`; when a reader was open and `LibraryRepository.manga(key:)` and its chapter exist, the reader opens and `ReaderModel.open(_:page:provider:)` gets the saved page. A missing title or chapter is skipped.
- `UserDefaults` is used instead of `@SceneStorage` (spec, "Reader presentation and state restoration"): scene storage is written only when the scene backgrounds and is dropped on reinstall, so a foreground kill (#5) or a push install (#3) would lose it.
- Incognito (decided, `DECISIONS.md` Round 2): while global incognito is on, or the open title's source is in `Pref.incognitoSources`, the snapshot holds only the selected tab. The manga ref and reader fields are written as nil, so a snapshot saved earlier for that title is overwritten too. The check is the existing `LibraryRepository.isIncognito(sourceId:)` (`LibraryRepository+Reader.swift:25-27`), the same one `saveProgress` uses (`LibraryRepository.swift:266`); tests set the repository's `preferences` to the isolated suite.

## Design direction
None.

## Seams
- `AppNavigatorTests` with an isolated `UserDefaults(suiteName:)` and `LibraryRepository.inMemory()`: a snapshot written for tab Browse, path `[.source("s"), .manga(a)]` and reader (a, chapter 2, page 7) restores to tab Browse, path `[.manga(a)]`, reader on chapter 2 with page 7; a snapshot naming a deleted title restores the tab only; with global incognito on, and separately with the title's source in `Pref.incognitoSources`, the same state saves and restores the tab only (path empty, no reader).
- `ReaderModel` (`ReaderModelTests.swift`): `open(chapter, page: 7, provider:)` sets `currentPage` to 7 for a chapter with at least 8 pages (uses `SourceFixture.extensions(pageCount: 10)`).

## Reuse first
- `AppNavigator` paths and reader state (tickets 02, 08).
- `Pref` key pattern (`Ahoge/App/Preferences.swift`), `LibraryRepository.manga(key:)` (`LibraryRepository.swift:162`).
- `LibraryRepository.isIncognito(sourceId:)` (`LibraryRepository+Reader.swift:25`).
- `ReaderModel.open(_:page:provider:)` (`ReaderModel.swift:99`).

## Acceptance criteria
- [ ] Cold launch restores the tab, `[.manga(ref)]` and the reader at its chapter and page (unit tests above pass in CI).
- [ ] A snapshot pointing at a missing title or chapter does not crash and restores the tab.
- [ ] While incognito applies to the open title (global or per-source), only the tab is saved; the manga page and reader position are not (unit tests above pass in CI).
- [ ] The snapshot key is not in `Pref.backupNames`.
- [ ] Manual check listed for the user: open a chapter at page 5, switch apps, kill Ahoge from Xcode or let iOS evict it, reopen: same tab, page and reader page.
- [ ] Committed with `Fixes #4` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Restoring intermediate screens (source browse, global search), scroll positions, search text or sheets.
