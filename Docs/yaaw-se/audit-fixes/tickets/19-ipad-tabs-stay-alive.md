# 19: iPad sidebar keeps every tab's screens alive

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 18
**Issue:** Part of #11

## What to build
On iPad, picking another sidebar item and coming back shows the screen the user left, as tabs do on iPhone. Today the detail column renders `screen(navigator.tab)` through a `switch` (`Ahoge/App/RootView.swift:211,236-244`), which destroys the previous tab's stack.

- The split view's detail column holds all five tab screens at once and shows only the selected one (for example a `ZStack` with the others hidden and not hit-testable, or a `TabView` with its bar hidden). Each keeps its own `NavigationStack` bound to its path from ticket 02.
- Logic that ran on appear moves to tab selection, because hidden screens do not disappear and reappear:
  - `UpdatesView` (`Ahoge/Features/Updates/UpdatesView.swift:158-160`): the `visible` flag and the `lastSeen` stamp follow `navigator.tab == .updates` (on change and on first appear when selected), not `onAppear`/`onDisappear`.
  - `HistoryView` (`Ahoge/Features/History/HistoryView.swift:75`): `reload` runs when `navigator.tab` becomes `.history`, as well as on first appear and after the reader closes.
- iPhone behaviour stays the same (TabView already keeps tabs alive; the tab-change handlers must also work there).

## Design direction
None. The sidebar and detail look unchanged.

## Seams
- Unit test on the "Updates seen" rule if it is factored into a function (selected tab and update time in, new `lastSeen` out). The layout itself is checked by the CI simulator build.

## Reuse first
- `RootView.screen(_:)` and `sidebarSelection` (`RootView.swift:236-249`), `AppNavigator.tab`.

## Acceptance criteria
- [ ] The detail column no longer switches between screens; all five exist.
- [ ] Updates and History refresh on tab selection on both iPad and iPhone.
- [ ] Manual check listed for the user: on iPad, Browse > a source > a title, select Library, select Browse: the title is still open.
- [ ] Committed with `Part of #11` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Deep-link routing (ticket 20).
