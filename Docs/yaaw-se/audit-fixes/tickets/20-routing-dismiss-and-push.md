# 20: Notification taps and deep links dismiss covers, then push on Library

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 08, 19
**Issue:** Fixes #11

## What to build
A notification tap or deep link always shows its screen. Today `AppNavigator.open` switches to Library and sets `pendingRoute`, but a sheet or the reader in another tab stays over it, and `LibraryView` replaces the Library path (`path = [route]`, `LibraryView.swift:156`), which can pop a manga page that owns something open.

- `AppNavigator.open(_ route:)` closes the reader (ticket 08's state), raises a dismiss request, selects Library and appends the route to the Library path. `pendingRoute` and the handler in `LibraryView` (`:152-157`) go.
- A shared view modifier, applied to every tab-screen sheet and full-screen cover, clears its presentation state when the dismiss request fires. Sheets in: `LibraryView` (`:123-126`), `MangaDetailView` (`:86-98,108-125`), `SourceBrowseView` (`:203,218`), `GlobalSearchView` (`:58`), `ExtensionsView` (`:60`), `MoreView` (`:185-186`), `DataStorageView` (`:143`), `MangaGrid` (`:43`). Reader sheets close with the reader.
- `UpdateNotifier.handleTap` (`Ahoge/Library/UpdateNotifier.swift:75-85`) and `RootView.onOpenURL` keep calling `navigator.open`.

## Design direction
None.

## Seams
- `AppNavigatorTests`: with Library path `[.manga(a)]`, the reader open and tab Browse, `open(.manga(b))` gives tab Library, path `[.manga(a), .manga(b)]`, reader nil, and a changed dismiss request; `open(.globalSearch("q"))` from a deep link appends the same way.
- `DeepLinkTests` (existing) still pass.

## Reuse first
- `AppNavigator.open` overloads (`Ahoge/App/AppNavigator.swift:39-59`), reader state from ticket 08, tab paths from ticket 02.

## Acceptance criteria
- [ ] `grep -rn "pendingRoute" Ahoge` finds nothing.
- [ ] Every sheet and cover listed above uses the shared modifier (list in the report).
- [ ] Tests pass in CI.
- [ ] Committed with `Fixes #11` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Alerts and confirmation dialogs (not covered by the decision).
