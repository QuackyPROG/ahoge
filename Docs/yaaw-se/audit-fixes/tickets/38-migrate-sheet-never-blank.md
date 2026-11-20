# 38: The migrate sheet is never blank

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 07
**Issue:** Part of #12

## What to build
Tapping a result in a migrate search never opens an empty sheet with no Cancel button. Today the sheet uses `isPresented:` and builds `MigrateSheet` only `if let old = repo.manga(...)` (`Ahoge/Features/Browse/GlobalSearchView.swift:58-62`); after Clear database (or a migration elsewhere) the old entry is gone and the sheet is empty.

- The tapped result sets an `Identifiable` item that already holds the old `LibraryManga` (looked up when tapped) and the target ref; the sheet is `sheet(item:)`.
- When the old entry no longer exists at tap time, no sheet opens; the screen shows a message ("This title is no longer in your library.") using the screen's existing alert or inline style, and the user can go back.

## Design direction
None.

## Seams
- No unit seam for sheet presentation. If the lookup and the "gone" decision are factored into a small function on the screen's model, test it with `LibraryRepository.inMemory()`: present when the entry exists, message when not. Otherwise the CI build checks it; manual check listed for the user.

## Reuse first
- `MigrateSheet(old:target:onDone:)` (`Ahoge/Features/Migration/MigrateSheet.swift:5-9`), `finishMigration` from ticket 07.

## Acceptance criteria
- [ ] No `if let` inside the migrate sheet's content closure.
- [ ] CI build and tests pass.
- [ ] Committed with `Part of #12` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
History's blank cover (fixed by ticket 08).
