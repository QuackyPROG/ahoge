# 51: Metadata refresh keeps fields the source returns empty

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Part of #14

## What to build
Refreshing a title's details no longer blanks its author, artist, summary, genres or status when the source returns nothing for them. Today `upsert(sourceId:url:details:)` overwrites them unconditionally (`Ahoge/Library/LibraryRepository.swift:189-193`).

- Each of author, artist and summary is replaced only by a non-empty string (after trimming whitespace); genres only by a non-empty list; status only by a value other than `unknown`, which is what `MangaDetails` decodes a missing status to (`Ahoge/SourceRuntime/JS/SourceModels.swift:44`). Title and cover keep their existing rules (`:187-188`).

## Design direction
None.

## Seams
- `LibraryRepositoryTests` on `inMemory()`: a title with author "A", genres ["x"], status "ongoing"; upsert details with author "", genres [], status "unknown": all three stay; upsert with author "B": author becomes "B".

## Reuse first
- `LibraryRepository.upsert(sourceId:url:details:keepTitle:)` (`LibraryRepository.swift:183-196`), `String.nonEmpty` if it exists in `Ahoge/Features/Shared/StringExtensions.swift` (used as `.nonEmpty` in `MangaDetailView.swift:227`).

## Acceptance criteria
- [ ] Tests pass in CI.
- [ ] Committed with `Part of #14` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
#14 items 4 and 5.
