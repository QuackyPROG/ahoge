# 48: Cancelling while a chapter is zipped leaves nothing behind

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Part of #13

## What to build
Cancelling a download while it is being zipped into a `.cbz` leaves no archive and no folder, so "Reindex downloads" cannot bring the cancelled chapter back. Today `cancel` deletes the files (`Ahoge/Downloads/DownloadManager.swift:164-176`, `:171`) while the detached `finish` (`:380`) keeps writing and moves the archive into place.

- The zipping step checks a cancellation signal before moving the temporary archive into place (`DownloadStore.finish`, `Ahoge/Downloads/DownloadStore.swift:94-97`). When cancelled it removes its temporary file and the folder and throws `CancellationError`. Pass the signal in (the detached task's cancellation, with `cancel` cancelling that task as well as the worker, or a closure that asks `DownloadManager`).
- After the detached task returns, `run` removes any archive for a cancelled key before returning (covers a race at the last instruction).

## Design direction
None.

## Seams
- `DownloadStore` unit test: call `finish(location, zip: true, isCancelled: { true })` (or the chosen shape) on a folder with pages: no `.cbz`, no `.tmp`, no folder remain and it throws.
- `DownloadManagerTests`: with "Save as CBZ" on and a store hook that blocks inside zipping, cancel the chapter, release the hook: after `waitUntilIdle()`, no files for it, and `reindex()` does not mark it downloaded.

## Reuse first
- `DownloadStore.finish` and `remove` (`DownloadStore.swift:82-112`), `DownloadManager.cancel`, `run` (`DownloadManager.swift:164-176,343-388`), `testCancelRemovesPartialFiles` (`DownloadManagerTests.swift:131`).

## Acceptance criteria
- [ ] Tests pass in CI.
- [ ] Committed with `Part of #13` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Background transport (ticket 49).
