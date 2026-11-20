# 46: Opening a CBZ download unpacks it off the main thread

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Part of #13

## What to build
Opening a downloaded CBZ chapter that is not in the chapter cache no longer freezes the UI for seconds. Today `PageProvider` (`@MainActor`, `Ahoge/Downloads/PageProvider.swift:19-27`) calls `DownloadManager.localPages` → `DownloadStore.localPages` → `ZipArchive.extractAll` (`Ahoge/Downloads/DownloadStore.swift:129-148`) synchronously on the main actor, with a byte-by-byte CRC (`Ahoge/Services/ZipArchive.swift:256-263`).

- `DownloadManager` gets an `async` variant of `localPages(_:)` that reads the index on the main actor and runs `DownloadStore.localPages` in `Task.detached` (`DownloadStore` is `Sendable`). `PageProvider.pages(for:)` awaits it. The sync `localPages` stays for callers that only need already-unpacked folders, or is removed if nothing else uses it.
- If ticket 14 has made the remote lookup injectable, keep that shape: downloads first, then the lookup.

## Design direction
None.

## Seams
- `DownloadManagerTests` / `PageProviderTests`: with "Save as CBZ" on, download a chapter, clear the chapter cache, `await provider.pages(for:)` returns the pages, and a probe shows the unpack did not run on the main thread (for example `DownloadStore` records `Thread.isMainThread` in a test hook, or the test asserts the call completes while the main actor services another task).

## Reuse first
- `DownloadStore.localPages` (`DownloadStore.swift:129-148`), `testCBZChapterIsOneArchiveAndReadsBackItsPages` (`Tests/AhogeTests/DownloadManagerTests.swift:196`) for setup.

## Acceptance criteria
- [ ] No `ZipArchive.extractAll` call on the main actor (diff shows the detached task).
- [ ] Tests pass in CI.
- [ ] Committed with `Part of #13` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Making the CRC loop faster.
