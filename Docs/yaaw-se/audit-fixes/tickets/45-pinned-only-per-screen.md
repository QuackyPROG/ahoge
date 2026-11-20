# 45: "Pinned only" re-runs only the screen it is toggled on

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 08, 38, 39, 40, 41, 42, 43, 44
**Issue:** Fixes #12

## What to build
Toggling "Pinned only" in one Global search screen no longer re-runs the search in every Global search screen in the stack. Today `pinnedOnly` is `@AppStorage` (`Ahoge/Features/Browse/GlobalSearchView.swift:21`) and each screen re-runs on change (`:56`).

- `pinnedOnly` becomes `@State`, initialised from `Pref.globalSearchPinnedOnly` when the screen is created. Toggling it saves the preference (so new screens start from the last choice) and re-runs only this screen's search.

## Design direction
None.

## Seams
- No unit seam for two live screens. `GlobalSearch.eligible(…, pinnedOnly:)` (existing tests) still covers the filter. CI build; manual check listed for the user.

## Reuse first
- `Pref.globalSearchPinnedOnly`, `GlobalSearchScreen.start()` (`GlobalSearchView.swift:66-76`).

## Acceptance criteria
- [ ] `GlobalSearchView.swift` has no `@AppStorage` for pinned-only.
- [ ] This is the last #12 ticket: items 1-8 are done (item 2 by ticket 08).
- [ ] Committed with `Fixes #12` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Other global search chips.
