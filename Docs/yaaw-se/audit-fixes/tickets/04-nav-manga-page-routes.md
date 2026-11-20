# 04: Manga page pushes "Search all sources" and Migrate as routes

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 02
**Issue:** Part of #2

## What to build
On a manga page, a genre's "Search all sources" and the Migrate button push their screens as routes. A result or source header tapped there then opens on top, not underneath.

- `MangaDetailView` (`Ahoge/Features/Manga/MangaDetailView.swift`): remove `navigationDestination(item: $globalQuery)` and `navigationDestination(item: $migrating)` (`:99-100`) and the `globalQuery` and `migrating` state (`:30-32`). The genre context menu (`:303`) pushes `.globalSearch(genre)`; the Migrate action (`:261`) pushes `.migrate(manga.ref)`. Both through `AppNavigator.push`.

## Design direction
None.

## Seams
- `AppNavigatorTests`: on a Library path `[.manga(a)]`, pushing `.migrate(a)` and then a value link `.sourceSearch(id, query:)` gives `[.manga(a), .migrate(a), .sourceSearch(…)]`.

## Reuse first
- `AppNavigator.push` (ticket 02).
- `Route.globalSearch`, `Route.migrate` (`Ahoge/App/Route.swift`).

## Acceptance criteria
- [ ] `grep -n "navigationDestination(item:" Ahoge/Features/Manga/MangaDetailView.swift` finds nothing.
- [ ] The `AppNavigatorTests` case passes in CI.
- [ ] Manual check listed for the user: Library > a title > long-press a genre > Search all sources > tap a result shows that manga page at once.
- [ ] Committed with `Part of #2` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
What happens after a migration finishes (ticket 07). The migrate sheet's blank state (ticket 38).
