# 21: Auto-backup encodes and writes off the main thread under a background task

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Part of #6

## What to build
Leaving the app no longer blocks the main thread while a backup is encoded, compressed and written, and iOS gives the backup the time it needs. Today `RootView` calls `AutoBackup.runIfDue` synchronously on `.background` (`Ahoge/App/RootView.swift:164-165`) with no background task assertion, and the BGTask path sets no expiration handler (`Ahoge/Library/BackgroundRefresh.swift:82-90`).

- `AutoBackup.runIfDue` becomes `async`. It checks the schedule and takes the snapshot (`BackupService.snapshot`) on the main actor, then encodes (`BackupCodec.encode`) and writes in a detached task. It sets `Pref.autoBackupLast` and rotates after the write succeeds. The destination folder becomes a parameter (default `AutoBackup.folder()`) so tests use a temp folder.
- The `.background` call site wraps the work in `UIApplication.shared.beginBackgroundTask(withName:expirationHandler:)` and ends it when done; the expiration handler ends it too (Apple: an app that does not end its tasks "in a timely manner" is terminated; `applicationDidEnterBackground` "has five seconds", checked 2026-11-20).
- `BackgroundRefresh.runBackup` sets `task.expirationHandler` (cancels the write task, completes with `success: false`) and completes with the real result.
- A second `.background` while a backup is running does not start another.

## Design direction
None.

## Seams
- `BackupScheduleTests` / a new `AutoBackupTests`: with an isolated `UserDefaults`, a temp folder, `LibraryRepository.inMemory()` and an `ExtensionStore` in a temp directory, `await runIfDue(…)` writes one file, sets `autoBackupLast`, and returns true; a second call before the interval returns false.

## Reuse first
- `AutoBackup`, `BackupSchedule` (`Ahoge/Backup/AutoBackup.swift`), `BackupService.snapshot` (`Ahoge/Backup/BackupService.swift:15-72`), `BackupCodec.encode`.

## Acceptance criteria
- [ ] No encode or file write runs on the main actor in `runIfDue` (the detached task is visible in the diff).
- [ ] Both call sites hold a background assertion or BGTask expiration handler.
- [ ] Tests pass in CI.
- [ ] Committed with `Part of #6` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Rotation rules (ticket 22).
