# 32: Restored chapters get unique source order

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Part of #10

## What to build
After a restore, every chapter of a title has a unique `sourceOrder` in reading order, so sorting, "mark previous read" and download-ahead pick the right chapters. Today chapters only in the backup keep the backup's `sourceOrder` (`Ahoge/Library/LibraryRepository+Backup.swift:96-105`), which collides with the local chapters' values.

- In `restoreManga`, after merging, when the title had local chapters and the backup added some: local chapters keep their relative order; backup-only chapters with a number ≥ 0 are inserted by chapter number (`sourceOrder` 0 is newest, so higher numbers go first); backup-only chapters with a number < 0 go after the local ones in backup order. Then `sourceOrder` is renumbered 0…n-1 and every changed record is saved in the same write.
- A title with no local chapters keeps the backup's order (renumbered only if it has duplicates).

## Design direction
None.

## Seams
- `BackupServiceTests` or `LibraryRepositoryTests` on `inMemory()`: local chapters 10, 9, 8 (orders 0-2) and a backup with chapters 11 (order 0) and 8.5 (order 1): result order by `sourceOrder` is 11, 10, 9, 8.5, 8 with orders 0-4 and no duplicates. `markPreviousRead` on 9 then marks 9, 8.5 and 8 only.

## Reuse first
- `restoreManga` (`LibraryRepository+Backup.swift:62-140`), `ChapterRecord.sourceOrder`, `markPreviousRead` (`LibraryRepository.swift:261-263`).

## Acceptance criteria
- [ ] Tests pass in CI; existing restore tests pass.
- [ ] Committed with `Part of #10` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Keeping backup-only chapters through the next refresh (ticket 26's carry-over handles same-number chapters; others are not on the source and go, as on Mihon).
