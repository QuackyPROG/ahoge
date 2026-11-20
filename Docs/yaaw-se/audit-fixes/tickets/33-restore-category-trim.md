# 33: Restore matches category names trimmed

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Part of #10

## What to build
Titles in a backup category named with stray spaces ("Reading ") land in that category after a restore, not in Default. Today names are trimmed when the category is created (`Ahoge/Library/LibraryRepository+Backup.swift:46-48`) but not when titles are matched to it (`:135-137`).

- Matching in `restoreManga` trims the backup's name the same way (`trimmingCharacters(in: .whitespacesAndNewlines)`, case-insensitive compare). Reuse `categoryId(named:)` lookup logic rather than a second copy.

## Design direction
None.

## Seams
- `BackupServiceTests`: a backup with category "Reading " and a title in it: after restore the title's categories contain the "Reading" category.

## Reuse first
- `categoryId(named:creating:)` (`LibraryRepository+Backup.swift:44-57`).

## Acceptance criteria
- [ ] Test passes in CI.
- [ ] Committed with `Part of #10` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Category ordering.
