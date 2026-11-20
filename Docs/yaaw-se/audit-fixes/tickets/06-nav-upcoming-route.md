# 06: Updates > Upcoming is a route

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 02
**Issue:** Part of #2

## What to build
Updates > Upcoming (calendar button) > a title opens that title's page on top. Today Upcoming is pushed with a view-based link (`UpdatesView.swift:131`), so the title's value link (`UpcomingView.swift:49`) lands underneath.

- `Route` gains `.upcoming`; `RouteView` shows `UpcomingView()`.
- `UpdatesView.swift:131`: `NavigationLink(value: Route.upcoming)`, same label and accessibility label.

## Design direction
None.

## Seams
- `AppNavigatorTests`: Updates path after the two taps is `[.upcoming, .manga(ref)]`.

## Reuse first
- `UpcomingView` (`Ahoge/Features/Updates/UpcomingView.swift`), `Route`/`RouteView` (`Ahoge/App/Route.swift`).

## Acceptance criteria
- [ ] `grep -n "NavigationLink { UpcomingView" -r Ahoge` finds nothing.
- [ ] Tests pass in CI.
- [ ] Committed with `Part of #2` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Updates' last-seen logic on iPad (ticket 19).
