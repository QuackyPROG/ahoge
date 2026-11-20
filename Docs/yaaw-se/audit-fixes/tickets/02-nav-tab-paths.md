# 02: Every tab owns a Route path in AppNavigator

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Part of #2

## What to build
The foundation for #2. Each of the five tabs has one `[Route]` navigation path, owned by `AppNavigator`, and each tab's root view binds its `NavigationStack(path:)` to it. Any view can push a screen onto the visible tab with one call. Nothing the user sees changes yet, except that Library keeps working through the shared path.

- `AppNavigator` (`Ahoge/App/AppNavigator.swift`) gets the per-tab paths (published), a binding helper for a tab's path, `push(_ route: Route)` that appends to the selected tab's path (`tab`), and `path(for:)` for tests.
- `LibraryView`'s `@State private var path` (`LibraryView.swift:24`) goes; its `NavigationStack(path:)` (`:82`), `openRandom` (`:333`) and the pending-route handler (`:153-157`) use the navigator's Library path. Keep today's `path = [route]` behaviour for pending routes; ticket 20 changes it.
- `BrowseView` (`BrowseView.swift:12`), `UpdatesView` (`UpdatesView.swift:41`), `HistoryView` (`HistoryView.swift:19`) and `MoreView` (`MoreView.swift:23`) bind their `NavigationStack` to their tab's path.
- Every stack keeps its `.navigationDestination(for: Route.self) { RouteView(route: $0) }`.

## Design direction
None.

## Seams
- `AppNavigator` unit tests in a new `Tests/AhogeTests/AppNavigatorTests.swift` (create a fresh `AppNavigator()`, not `.shared`; add an internal init if needed): `push` appends to the selected tab only; switching `tab` then pushing leaves the other tab's path unchanged; `open(.manga(ref))` still selects Library and sets `pendingRoute`.

## Reuse first
- `AppNavigator`, `AppTab` (`Ahoge/App/AppNavigator.swift`).
- `Route`, `RouteView` (`Ahoge/App/Route.swift`).
- The existing path pattern in `LibraryView` (`Ahoge/Features/Library/LibraryView.swift:24,82,151-157`).

## Acceptance criteria
- [ ] `grep -n "NavigationStack {" Ahoge/Features/{Browse/BrowseView,Updates/UpdatesView,History/HistoryView,More/MoreView}.swift` finds no tab-root stack without a path (sheet stacks elsewhere are unaffected).
- [ ] `LibraryView` has no local path state.
- [ ] `AppNavigatorTests` covers the three cases above and passes in CI.
- [ ] Committed with `Part of #2` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Removing `navigationDestination(item:)` (tickets 03, 04, 07), new `Route` cases (05, 06), deep-link behaviour (20), state restoration (09).
