# 37: Clear database removes cleared titles' covers and settings

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 29, 30, 31, 32, 33, 34, 35, 36
**Issue:** Fixes #10

## What to build
Clearing titles from the database also removes what only they used: custom cover files and their per-series reader and chapter-display settings. Today `clearNonLibrary` (`Ahoge/Library/LibraryRepository.swift:315-328`) deletes rows only.

- Before deleting, `clearNonLibrary` collects the cleared titles' `customCover` names. After the delete, a cover file is deleted when no remaining `manga` row uses it (the shared-file count in `LibraryRepository+Covers.swift:22-26`).
- Per-series settings of each cleared key are removed with the helper from ticket 36.

## Design direction
None.

## Seams
- `ClearDatabaseTests` with an isolated defaults suite: a cleared title with a custom cover and a reading mode: the cover file and the setting are gone; a cover file shared with a library title stays.

## Reuse first
- `setCoverFile`'s shared-file check (`LibraryRepository+Covers.swift:17-27`), `CoverStore.delete` (`Ahoge/Library/CoverStore.swift:35`), the per-series helper from ticket 36.

## Acceptance criteria
- [ ] Tests pass in CI.
- [ ] This is the last #10 ticket: tickets 29-36 are done.
- [ ] Committed with `Fixes #10` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Removing download files (titles with downloads are never cleared).
