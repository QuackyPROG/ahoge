# 30: Clear database keeps titles with any progress, bookmark or history

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Part of #10

## What to build
With "keep" on, Clear database no longer deletes half-read, bookmarked or recently read titles with their history. Today the rule spares only titles with a chapter where `read = 1` (`Ahoge/Library/LibraryRepository.swift:301-306`).

- The keep rule spares a non-library title when any of its chapters has `read = 1`, `lastPageRead > 0` or `bookmark = 1`, or when it has a `history` row.
- `ClearDatabaseView` (`Ahoge/Features/More/ClearDatabaseView.swift:16`): the toggle reads "Keep titles with progress or history" (it no longer says only "read chapters"). Footer unchanged.
- The parameter name `keepRead` can become `keepStarted` across `clearable`, `nonLibraryCounts`, `clearNonLibrary` and the view; update `ClearDatabaseTests`.

## Design direction
None.

## Seams
- `ClearDatabaseTests` on `inMemory()`: four non-library titles, one each with a read chapter, `lastPageRead` 3, a bookmark, a history row, plus one untouched: with keep on, only the untouched title is cleared; with keep off, all five are.

## Reuse first
- `LibraryRepository.clearable/nonLibraryCounts/clearNonLibrary` (`LibraryRepository.swift:301-328`), `ClearDatabaseTests` (`Tests/AhogeTests/ClearDatabaseTests.swift`).

## Acceptance criteria
- [ ] Tests pass in CI.
- [ ] Committed with `Part of #10` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Confirmation texts (ticket 31), cover and settings cleanup (ticket 37).
