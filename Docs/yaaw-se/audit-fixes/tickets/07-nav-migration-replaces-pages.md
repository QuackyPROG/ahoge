# 07: A finished migration replaces the old page and the migrate search

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 03, 04, 05, 06
**Issue:** Fixes #2

## What to build
After Migrate or Copy in the migrate sheet, the user sees the new entry's page, and Back never returns to a migrate search for an entry that left the library (Mihon's behaviour).

- `AppNavigator` gets `finishMigration(from old: MangaRef, to new: MangaRef)` that rewrites the selected tab's path with a pure rule, implemented as a static function on `[Route]` so it is testable on its own:
  - When the last `.migrate(old)` is directly after `.manga(old)`, both are replaced by `.manga(new)`.
  - Otherwise (started from More > Migrate) `.migrate(old)` and anything after it are popped, which leaves `.migrateTitles(sourceId)` on top.
  - No `.migrate(old)` on the path: no change.
- `GlobalSearchView` (`Ahoge/Features/Browse/GlobalSearchView.swift`): remove `navigationDestination(item: $migrated)` (`:63`) and the `migrated` state (`:28`); `MigrateSheet`'s `onDone` (`:60`) calls `finishMigration`.

## Design direction
None.

## Seams
- `AppNavigatorTests`, pure path rule: `[.manga(a), .migrate(a)]` → `[.manga(b)]`; `[.globalSearch("x"), .manga(a), .migrate(a)]` → `[.globalSearch("x"), .manga(b)]`; `[.migrateSources, .migrateTitles("s"), .migrate(a)]` → `[.migrateSources, .migrateTitles("s")]`; `[.manga(a), .migrate(a), .sourceSearch(…)]` → `[.manga(b)]`; a path without `.migrate(a)` is unchanged.

## Reuse first
- `MigrateSheet.onDone` (`Ahoge/Features/Migration/MigrateSheet.swift:9,95-103`).
- The tab paths from ticket 02 and the routes from tickets 04 and 05.

## Acceptance criteria
- [ ] `grep -rn "navigationDestination(item:" Ahoge` finds nothing in the whole app.
- [ ] `grep -rn "NavigationLink {" Ahoge` lists only links to screens without value links (settings screens, `SourceFilterView`, `SourcePreferencesView`, `CategoriesView`); the list is in the report.
- [ ] The five path-rule cases pass in CI.
- [ ] Committed with `Fixes #2` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
The migrate sheet being blank when the old entry is gone (ticket 38).
