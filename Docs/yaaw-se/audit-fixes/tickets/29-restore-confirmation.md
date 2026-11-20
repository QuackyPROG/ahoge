# 29: Restore asks first and leaves settings alone by default

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Part of #10

## What to build
Picking a backup file no longer starts a restore at once. A confirmation dialog offers **Restore library** (default), **Restore library and settings** and **Cancel**. Only the second overwrites the settings in `Pref.backupNames` (which include `incognitoSources`, `requireUnlock`, download and backup settings). Today the restore starts on pick (`Ahoge/Features/More/DataStorageView.swift:137-141`) and always writes every key (`Ahoge/Backup/BackupService.swift:105-107`).

- `BackupService.restore` gets a `includingSettings: Bool` parameter (no default, so every caller chooses). Repositories, installed sources, categories and titles are restored in both cases.
- `DataStorageView`: the file importer stores the picked URL (keeping security-scoped access for the restore) and presents a `confirmationDialog` in the style of the existing one at `:146-153`; the chosen button runs `restore(from:includingSettings:)`.

## Design direction
None.

## Seams
- `BackupServiceTests` with isolated defaults: a backup whose preferences turn on `Pref.incognitoSources = ["x"]`: restore with `includingSettings: false` leaves the key unset and still restores titles; with `true` it sets it.

## Reuse first
- `BackupService.restore` (`BackupService.swift:85-116`), `DataStorageView.restore(from:)` (`DataStorageView.swift:202-213`), the confirmation dialog style at `DataStorageView.swift:146-153`.

## Acceptance criteria
- [ ] Picking a file shows the three choices; "Restore library" is the first (default) action.
- [ ] Tests pass in CI.
- [ ] Committed with `Part of #10` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Mihon import differences (ticket 52).
