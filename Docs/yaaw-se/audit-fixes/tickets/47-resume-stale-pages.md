# 47: A resumed download keeps only pages saved for the same page list

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Part of #13

## What to build
A download that resumes after the source's page list changed (fewer pages, or a page that changed type such as `001.jpg` → `001.png`) ends with exactly the right pages. Today saved pages are recognised by index only (`Ahoge/Downloads/DownloadStore.swift:55-62`) and `finish` counts every file in the folder (`:82-99`).

- `DownloadStore.begin` writes a small manifest in the chapter folder (a dot-file, so `pages(in:)` ignores it) with the page URLs. On resume, when the manifest differs from the new page list, the saved page files are deleted before downloading. A folder without a manifest (from an older version) is treated as different.
- `finish` keeps exactly one file per page index `0..<count` (when two files share an index, the newest stays) and deletes files with an index ≥ count. The manifest is removed with the partial marker.

## Design direction
None.

## Seams
- `DownloadManagerTests` with `StubTransport` and `SourceFixture`: write `001.jpg`–`003.jpg` and a manifest for 3 pages, then resume with a 2-page list whose stub transport answers page 1 with PNG bytes: the finished chapter folder holds exactly two page files (`001.png`, `002.jpg`), the old `001.jpg` and `003.jpg` are gone, and the download row's page count is 2.

## Reuse first
- `DownloadStore.begin/existingPages/finish` (`DownloadStore.swift:45-99`), `DownloadStore.fileExtension(for:)`.

## Acceptance criteria
- [ ] Tests pass in CI; existing download tests pass.
- [ ] Committed with `Part of #13` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Cancel during zip (ticket 48).
