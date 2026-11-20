# 03: Browse pushes Global search, Open link and Extension details as routes

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 02
**Issue:** Part of #2

## What to build
In Browse, a search result or source header tapped in "Search all sources" opens on top of Global search, and a genre or author tapped on a manga page reached through "Open link" opens on top of that page. Today they land underneath until Back is tapped.

- `SourcesView` (`Ahoge/Features/Browse/SourcesView.swift`): remove the three `navigationDestination(item:)` modifiers (`:71-73`) and the `searching`, `details` and `opened` state. Search submit (`:67-70`) pushes `.globalSearch(query)`; the context menu's "Extension details" (`:131`) pushes `.extensionDetails(id)`; `openLink()` (`:136-147`) pushes `.manga(ref)` or `.globalSearch(query)`. All through `AppNavigator.push`.
- `ExtensionsView` (`Ahoge/Features/Browse/ExtensionsView.swift:61`): remove `navigationDestination(item: $details)` and the `details` state; whatever set `details` pushes `.extensionDetails(id)`.

## Design direction
None.

## Seams
- `AppNavigatorTests`: pushing `.globalSearch("q")` then `.manga(ref)` on Browse gives the path `[.globalSearch("q"), .manga(ref)]` (the value link appends after the pushed route, which is the order SwiftUI renders).
- No unit seam for the view wiring; the grep criterion below checks it.

## Reuse first
- `AppNavigator.push` from ticket 02.
- `Route.globalSearch`, `.extensionDetails`, `.manga` (`Ahoge/App/Route.swift`).
- `DeepLinkResolver.resolve` already used by `openLink()`.

## Acceptance criteria
- [ ] `grep -rn "navigationDestination(item:" Ahoge/Features/Browse/SourcesView.swift Ahoge/Features/Browse/ExtensionsView.swift` finds nothing.
- [ ] The `AppNavigatorTests` case passes in CI.
- [ ] Manual check listed in the report for the user: Browse > Sources > search "a" > tap a result shows the manga page at once; Back returns to Global search.
- [ ] Committed with `Part of #2` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Clearing the search field after submit (ticket 44). The Browse picker width (ticket 42).
