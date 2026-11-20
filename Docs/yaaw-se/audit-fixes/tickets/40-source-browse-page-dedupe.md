# 40: Source browse de-duplicates within one page

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Part of #12

## What to build
A page from a source that lists the same title twice shows it once. `SourceBrowseModel.loadMore` filters out titles seen on earlier pages but not duplicates inside the new page (`Ahoge/Features/Browse/SourceBrowseView.swift:87-88`).

- The filter tracks URLs added so far while walking the new page, so a URL is added once whether it repeats across pages or within one. The first load (if it goes through another path) gets the same rule.

## Design direction
None.

## Seams
- `SourceBrowseModelTests` with the model's fetch closure returning `[a, b, a]` on page 1 and `[b, c]` on page 2: items are `[a, b, c]`.

## Reuse first
- `SourceBrowseModel` fetch closure and `loadMore` (`SourceBrowseView.swift:80-95`), existing `SourceBrowseModelTests`.

## Acceptance criteria
- [ ] Test passes in CI.
- [ ] Committed with `Part of #12` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Global search (ticket 39).
