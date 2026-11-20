# 26: Carry chapter state when a chapter's URL changes

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Part of #8

## What to build
When a source changes its domain or chapter URL format, a library update keeps each chapter's read state, bookmark, last page, first-seen date and history, and does not flood Updates or notify. Today `ChapterMerge` matches by URL only (`Ahoge/Library/ChapterMerge.swift:19-39`), `applyChapters` deletes the unmatched chapters (`Ahoge/Library/LibraryRepository.swift:226-227`), their history cascades (`:102`), and `LibraryUpdater` counts the new keys as new (`Ahoge/Library/LibraryUpdater.swift:63-69`).

- `ChapterMerge` also returns the carry-over pairs (removed URL → added URL). Rule: chapter number ≥ 0 and equal. When several removed or several added chapters share that number, pair those with equal scanlator; when still more than one candidate on either side, skip that number.
- A carried chapter's merged state takes `read`, `lastPageRead` and `dateFetch` from the removed one. `applyChapters` sets `bookmark` on the new record and, in the same write, moves the history row to the new chapter key (`UPDATE history SET chapterKey = ? WHERE chapterKey = ?`) before deleting the old chapter row.
- `applyChapters` reports the carried pairs (return value or a property the updater reads). `LibraryUpdater` leaves carried chapters out of `found`, so they are not notified and not passed to `downloads.chaptersFound`.
- "Mark duplicate chapters read" (`LibraryRepository.swift:218-219`) still applies to added chapters without a carry.

## Design direction
None.

## Seams
- `ChapterMergeTests`: pairs for a pure URL change; ambiguity resolved by scanlator; skipped when still ambiguous; numbers < 0 never pair.
- `LibraryRepositoryTests` on `inMemory()`: a title with chapters `/old/1`, `/old/2` (1 read, 2 bookmarked with `lastPageRead` 4 and a history row) re-fetched as `/new/1`, `/new/2`: read, bookmark, last page and history are on the new keys; the old rows are gone.
- `UpdatesHistoryTests` or a `LibraryUpdater` test with `SourceFixture`: the re-keyed chapters do not appear in `repo.updates(since:)` as new.

## Reuse first
- `ChapterMerge.merge` (`ChapterMerge.swift:18-40`), `LibraryRepository.applyChapters` (`LibraryRepository.swift:198-232`), `ChapterRecord.apply(state)`.

## Acceptance criteria
- [ ] All three test groups pass in CI.
- [ ] Committed with `Part of #8` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Download files and rows (ticket 27), orphan folders (ticket 28).
