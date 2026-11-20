# 35: Migration carries last page read and history

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Part of #10

## What to build
Migrating a title with "Chapters" on keeps where the user stopped in each chapter and their reading history. Today only `read` and `bookmark` are copied (`Ahoge/Library/LibraryRepository+Migrate.swift:62-82`); `lastPageRead` and history stay on the old entry.

- In `carryChapters`, a new chapter matched by number also takes the largest `lastPageRead` of its matches (when it is not read).
- In the same write, history rows of matched old chapters are copied to the new chapter keys (`INSERT … ON CONFLICT(chapterKey) DO UPDATE SET lastRead = MAX(…), timeRead = MAX(…)`, as restore does at `LibraryRepository+Backup.swift:118-124`), with the new manga key. The old entry's history rows are not deleted (the decision says carry; the old entry's row stays in the database after Migrate too).
- `MigrateSheet`'s toggle text (`Ahoge/Features/Migration/MigrateSheet.swift:27`) reads "Chapters (read, progress, bookmarks, history)". `MigrateOptions.chapters`' doc comment says the same.

## Design direction
None.

## Seams
- `MigrateTests` on `inMemory()`: old chapter 3 at `lastPageRead` 5 with history (lastRead d, timeRead 120); after migrate, new chapter 3 has `lastPageRead` 5 and a history row (d, 120); a new chapter that already had newer history keeps the newer date; with "Chapters" off nothing is carried.

## Reuse first
- `carryChapters`, `migrate` (`LibraryRepository+Migrate.swift:21-82`), the history upsert SQL in `restoreManga`.

## Acceptance criteria
- [ ] Tests pass in CI; existing `MigrateTests` pass.
- [ ] Committed with `Part of #10` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Per-series reader settings (ticket 36).
