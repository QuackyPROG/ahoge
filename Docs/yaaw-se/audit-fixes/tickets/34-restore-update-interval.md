# 34: Restore keeps an existing title's Smart update interval

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Part of #10

## What to build
Restoring a backup no longer replaces a title's "Smart" update interval on this device with the backup's value. `updateInterval == nil` means Smart (`Ahoge/Library/UpdatePolicy.swift:46-52`, `UpdateIntervalRow.swift:14,36`), and today restore fills it whenever it is nil (`Ahoge/Library/LibraryRepository+Backup.swift:75`).

- The backup's `updateInterval` applies only when the title is new to the device (`isNew`, `:65-73`), like author, artist and the other metadata.

## Design direction
None.

## Seams
- `BackupServiceTests`: an existing title with `updateInterval` nil and a backup with 7 → stays nil; a title new to the device → 7.

## Reuse first
- `restoreManga`'s `isNew` branch (`LibraryRepository+Backup.swift:65-73`).

## Acceptance criteria
- [ ] Tests pass in CI.
- [ ] Committed with `Part of #10` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Other restore merge rules.
