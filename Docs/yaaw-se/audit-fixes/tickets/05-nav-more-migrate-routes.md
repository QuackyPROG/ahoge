# 05: More > Migrate screens become routes

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 02
**Issue:** Part of #2

## What to build
More > Migrate > a source > a title opens the migrate search on top. Today the two migrate list screens are pushed with view-based links, so the title's value link lands underneath them. The same applies when Migrate is opened from the settings search.

- `Route` (`Ahoge/App/Route.swift`) gains `.migrateSources` and `.migrateTitles(String)` (source id); `RouteView` shows `MigrateSourcesView()` and `MigrateTitlesView(sourceId:)`.
- `MigrateTitlesView` (`Ahoge/Features/Migration/MigrateSheet.swift:147`) becomes internal (not `private`) so `RouteView` can build it.
- `MoreView.swift:66`: `NavigationLink(value: Route.migrateSources)`.
- `MigrateSheet.swift:120`: `NavigationLink(value: Route.migrateTitles(id))`.
- `SettingsSearch.swift:143`: the `.migrate` destination pushes `Route.migrateSources` as a value link. The other destinations keep their view links (their screens contain no value links).

## Design direction
None.

## Seams
- `AppNavigatorTests`: More path after the three taps is `[.migrateSources, .migrateTitles("s"), .migrate(ref)]`.
- `SettingsSearchTests` (existing): still passes; add a case that the "Migrate" entry's destination is `.migrate` if one is missing.

## Reuse first
- `MigrateSourcesView`, `MigrateTitlesView` (`Ahoge/Features/Migration/MigrateSheet.swift:107-172`).
- `SettingsDestination` (`Ahoge/Features/More/SettingsSearch.swift:5-22`).

## Acceptance criteria
- [ ] `grep -n "NavigationLink { MigrateSourcesView\|NavigationLink { MigrateTitlesView" -r Ahoge` finds nothing.
- [ ] Settings search for "migrate" opens the migrate source list as a route (code path uses `Route.migrateSources`).
- [ ] Tests pass in CI.
- [ ] Committed with `Part of #2` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Returning to the titles list after a migration (ticket 07).
