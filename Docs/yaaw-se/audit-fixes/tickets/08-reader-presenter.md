# 08: The reader is presented from one place

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 02
**Issue:** Part of #4, Part of #12 (item 2)

## What to build
A prefactor for #4 and #11 that also fixes #12 item 2. The reader opens from one `fullScreenCover` in `RootView`, driven by `AppNavigator`. Opening the reader from Library ("continue"), Updates, History or a manga page behaves as today. History can no longer show a blank full-screen cover with no close button.

- `AppNavigator` gets the open reader as published state: the `LibraryManga` (strong reference), the `ChapterRecord` and the source id, plus `read(_ chapter:, in manga:)` and `closeReader()`.
- `RootView` (`Ahoge/App/RootView.swift`) presents `ReaderView(sourceId:manga:chapter:)` from that state, next to the onboarding cover.
- Remove the reader covers in `LibraryView.swift:147-149`, `UpdatesView.swift:155-157`, `HistoryView.swift:71-73` and `MangaDetailView.swift:134-136`; their callers call `navigator.read`.
- History's `reload` after the reader closes (`onDismiss: reload`, `HistoryView.swift:71`) keeps working: reload when the reader state goes back to nil.
- History passes the entry's `manga` (strong, from `HistoryEntry`) instead of the weak `chapter.manga` (`LibraryModels.swift:85`).
- `.readerDidClose` (`ReaderView.swift:170`, observed at `RootView.swift:170-172`) keeps working.

## Design direction
None.

## Seams
- `AppNavigatorTests`: `read` sets the reader state with the given manga and chapter; `closeReader` clears it; the manga is held even when no other reference exists (create it in a scope, drop the scope, check it is still there).

## Reuse first
- `ReaderView(sourceId:manga:chapter:)` (`Ahoge/Features/Reader/ReaderView.swift:60`).
- `HistoryEntry.manga`, `HistoryEntry.resumeChapter` (`Ahoge/Library/LibraryRepository+History.swift`).
- `AppNavigator` from ticket 02.

## Acceptance criteria
- [ ] `grep -rn "ReaderView(" Ahoge` shows exactly one call site, in `RootView`.
- [ ] No reader cover's content depends on `chapter.manga`.
- [ ] Tests pass in CI.
- [ ] Manual check listed for the user: open the reader from each of Library continue, Updates, History and a manga page; close it; History refreshes.
- [ ] Committed with `Part of #4` and `Part of #12` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Saving or restoring the reader (ticket 09). Dismissing the reader before routing (ticket 20).
