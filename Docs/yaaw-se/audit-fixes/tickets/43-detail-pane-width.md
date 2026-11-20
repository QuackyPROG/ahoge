# 43: Manga page details pane is not a fixed 400 pt

**Status:** ready
**Agent:** yaaw-designer
**Blocked by:** None
**Issue:** Part of #12

## What to build
In regular width (iPad, iPad Split View, large phones in landscape) the manga page's chapter list keeps a usable width. Today the details pane is fixed at 400 pt (`Ahoge/Features/Manga/MangaDetailView.swift:63-68`), so narrow regular widths squeeze the chapters.

- The details pane takes a share of the available width with a sensible minimum and maximum (for example about 40 %, never wider than 400 pt), so the chapter list always gets the larger part.

## Design direction
- Mode: polish an existing screen.
- Look: inherit. Same two lists, same divider, same header and chapter rows; no new components (DECISIONS: "Existing look and components stay"; "No new dependencies").
- Must not change: the compact-width single list; the header content; selection mode; the fast scroller.
- Success: at the narrowest regular width on iPad (about 507 pt in Split View) and on a full-width 13-inch iPad in landscape, the details pane is readable and the chapter list is at least as wide as the details pane. Verified by the CI simulator build; screenshots are not available in CI, so the report lists the manual check.

## Seams
- If the width rule is a pure function (available width → pane width), unit-test it: 507 → ≤ 253, 1366 → 400. Otherwise the CI build only.

## Reuse first
- `MangaDetailView.list(_:chapters:proxy:)` and the `sizeClass` branch (`MangaDetailView.swift:59-72,142-191`).

## Acceptance criteria
- [ ] No fixed 400 pt frame on the details pane.
- [ ] CI build passes; width-rule test passes if added.
- [ ] Committed with `Part of #12` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Switching the root layout by device (ticket 18).
