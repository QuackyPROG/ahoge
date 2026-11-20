# 22: Rotation deletes only automatic backups

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 21
**Issue:** Fixes #6

## What to build
A manual backup saved into Documents/Backups is never deleted by automatic backup rotation. Today rotation deletes the oldest `.ahbk` files by extension only (`Ahoge/Backup/AutoBackup.swift:50-58`), and manual exports use the same name pattern (`BackupFile.name`, `Ahoge/Backup/BackupFile.swift:13-20`, used at `DataStorageView.swift:196`).

- Automatic backups are named `ahoge_auto_YYYY-MM-DD_HH-mm.ahbk`. `BackupFile` gets a way to make that name (a parameter or a second function) and a test of whether a file name is automatic.
- Rotation considers only files whose names match the automatic pattern. Manual exports keep `ahoge_YYYY-MM-DD_HH-mm.ahbk`.
- The footer text in Data and storage stays accurate; change it only if it describes rotation.
- Automatic backups written before this change have the manual pattern and are no longer rotated (spec, Out of scope).

## Design direction
None.

## Seams
- `BackupScheduleTests`: the automatic-name test accepts `ahoge_auto_2026-11-20_10-00.ahbk` and rejects `ahoge_2026-11-20_10-00.ahbk` and `notes.ahbk`.
- `AutoBackupTests` (from ticket 21): a temp folder with 2 manual files and 5 automatic files, `keep` 3: after a run, both manual files remain and 3 automatic files remain (the newest).

## Reuse first
- `BackupSchedule.rotate` (`Ahoge/Backup/AutoBackup.swift:15-18`), `BackupFile.name` (`Ahoge/Backup/BackupFile.swift:13-20`).

## Acceptance criteria
- [ ] Manual files survive rotation (test passes in CI).
- [ ] New automatic files carry the `ahoge_auto_` prefix.
- [ ] Committed with `Fixes #6` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Moving or renaming existing backup files.
