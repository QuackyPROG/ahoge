# 39: Global search shows each result once

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Part of #12

## What to build
A source that returns the same title twice in one search no longer gives missing or repeated cards. `GlobalSearchView` uses `ForEach(manga, id: \.url)` (`Ahoge/Features/Browse/GlobalSearchView.swift:144`), and `GlobalSearch.search` stores the page as returned (`Ahoge/Features/Browse/GlobalSearch.swift:93-97`).

- `GlobalSearch` de-duplicates each source's results by URL, keeping the first occurrence and the order.

## Design direction
None.

## Seams
- `GlobalSearchTests` with a `Searcher` closure returning `[a, b, a]` for one source: the result's `.done` list is `[a, b]`.

## Reuse first
- `GlobalSearch(searcher:)` (`GlobalSearch.swift:34`), the de-duplication in `SourceBrowseModel` (`Ahoge/Features/Browse/SourceBrowseView.swift:87-88`).

## Acceptance criteria
- [ ] Test passes in CI.
- [ ] Committed with `Part of #12` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Within-page duplicates in source browse (ticket 40).
