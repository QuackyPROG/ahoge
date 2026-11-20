# 18: Choose split view or tabs by device, not size class

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 08
**Issue:** Part of #11

## What to build
Resizing an iPad window (Split View, Slide Over) or rotating a Plus/Pro Max iPhone no longer rebuilds every screen. Today `RootView.tabs` picks `NavigationSplitView` or `TabView` from `horizontalSizeClass` (`Ahoge/App/RootView.swift:110,200`), so a size-class change throws away every stack, search field, scroll position, sheet and the reader.

- The choice uses `UIDevice.current.userInterfaceIdiom == .pad` (split view) or anything else (tabs), read once.
- `RootView` stops reading `horizontalSizeClass` for this. `MangaDetailView`'s two-pane layout still follows size class (`MangaDetailView.swift:63`).
- Do this after ticket 09 when 09 is unblocked, since both edit `RootView`; it does not depend on 09's code.

## Design direction
None.

## Seams
- The choice is a tiny pure function (`RootLayout.forIdiom(_:)` or similar) with a unit test: `.pad` → split, `.phone` → tabs. The rest is checked by the CI simulator build.

## Reuse first
- `RootView.tabs(badge:)` (`Ahoge/App/RootView.swift:198-234`).

## Acceptance criteria
- [ ] `grep -n "horizontalSizeClass" Ahoge/App/RootView.swift` finds nothing.
- [ ] Unit test passes in CI.
- [ ] Manual check listed for the user: on an iPad, open a manga page, resize to Slide Over and back; the page is still there.
- [ ] Committed with `Part of #11` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Keeping iPad tab screens alive (ticket 19).
