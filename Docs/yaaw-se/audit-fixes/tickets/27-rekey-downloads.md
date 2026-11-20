# 27: Re-link or delete downloads of re-keyed and removed chapters

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 26
**Issue:** Part of #8

## What to build
A chapter whose URL changed keeps its download, and a chapter that disappeared from the source does not leave untracked files or a wrong "downloaded" mark. Today the `download` row cascades with the chapter row (`Ahoge/Library/LibraryRepository.swift:132`) while files and the in-memory index stay, and `completed()` writes inside `try?` and marks a chapter downloaded even when its foreign key fails (`Ahoge/Downloads/DownloadManager.swift:423-433`).

- `LibraryRepository` gets a callback like `didMarkRead` (`LibraryRepository.swift:21`): told, before the chapter rows are deleted, which chapters were carried (old key → new key) and which were removed. `DownloadManager` wires it as it wires `didMarkRead` (`DownloadManager.swift:105`).
- Carried: move the chapter folder or `.cbz` (`DownloadStore.chapterDirectory`/`archive`, `Ahoge/Downloads/DownloadStore.swift:30-36`) to the new key's location, drop the old unpacked cache copy, update the `download` row's `chapterKey` and the `downloaded` index. A queued item for the old key is cancelled and the new chapter queued in its place.
- Removed: delete the files (`DownloadStore.remove`), the index entry, and cancel a queued item.
- `completed()` marks the chapter downloaded in memory only when its row was written; otherwise it removes the files and logs.

## Design direction
None.

## Seams
- `DownloadManagerTests` with `StubTransport`, `SourceFixture` and temp folders: download chapter 1, re-fetch the title with chapter 1 under a new URL: `isDownloaded(newKey)` is true, `localPages(newKey)` returns the pages, no folder remains under the old key's hash. Re-fetch without chapter 2 after downloading it: its files are gone and `isDownloaded` is false.
- `completed()` with a missing chapter row: not marked downloaded (cancel the chapter row before the download finishes, or delete the row then let the queue finish).

## Reuse first
- `didMarkRead` callback pattern, `DownloadStore.Location`, `DownloadStore.remove`, `DownloadManager.cancel` (`DownloadManager.swift:164-176`).

## Acceptance criteria
- [ ] Tests pass in CI.
- [ ] Committed with `Part of #8` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Sweeping folders with no chapter row (ticket 28).
