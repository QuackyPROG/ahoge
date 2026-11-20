# 28: Reindex deletes download folders that match no chapter

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 27
**Issue:** Fixes #8

## What to build
More > Data and storage > Reindex downloads also removes leftovers: chapter folders and `.cbz` files whose chapter key matches no chapter row. Today `reindex` only walks chapter rows (`Ahoge/Downloads/DownloadManager.swift:215-239`), so nothing cleans orphan folders.

- `reindex` builds the set of expected locations from chapter rows, lists what is on disk under each manga folder (`DownloadStore.mangaFolders`, `Ahoge/Downloads/DownloadStore.swift:166-178`), and deletes chapter folders and archives not in the set. Folders still `.partial` for a queued chapter are kept. Empty manga folders go too.
- `DownloadStore` gets a function listing a manga folder's chapter entries (folder and archive names) so the sweep works on hashes.

## Design direction
None.

## Seams
- `DownloadManagerTests`: download chapter 1, create an extra chapter folder with a page and an extra `.cbz` under the same manga folder with hashes of keys that have no row, run `reindex`: both extras are gone, chapter 1 is still downloaded. A `.partial` folder of a queued chapter survives.

## Reuse first
- `DownloadManager.reindex` (`DownloadManager.swift:215-239`), `DownloadStore.hash`, `mangaFolders`, `mangaFolder` (`DownloadStore.swift:23,166-178`), `DownloadStore.remove`.

## Acceptance criteria
- [ ] Test passes in CI; existing `testReindexRestoresRowsFromDiskAndIgnoresPartialChapters` still passes.
- [ ] Committed with `Fixes #8` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Sweeping on launch (only on Reindex, as decided).
