# 44: Sources' search field resets after a search

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 03
**Issue:** Part of #12

## What to build
After submitting "Search all sources" and coming back, the Sources search field is empty and not active. Today `globalQuery` is never cleared or dismissed after submit (`Ahoge/Features/Browse/SourcesView.swift:66-70`).

- On submit, after pushing `.globalSearch(query)` (ticket 03), clear `globalQuery` and end the search field's active state (`@Environment(\.dismissSearch)` from a view inside the `searchable` hierarchy, or `isPresented:` binding on `searchable`, iOS 17).

## Design direction
None.

## Seams
- No unit seam (view state). CI build; manual check listed for the user: search, open a result, Back twice: the field is empty and the list shows sources.

## Reuse first
- `SourcesView`'s `searchable` and `onSubmit` (`SourcesView.swift:66-70`).

## Acceptance criteria
- [ ] `globalQuery` is cleared on submit and the search is dismissed.
- [ ] CI build passes.
- [ ] Committed with `Part of #12` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Global search's own field.
