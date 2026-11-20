# 42: Browse picker fits narrow phones and large text

**Status:** ready
**Agent:** yaaw-designer
**Blocked by:** 02
**Issue:** Part of #12

## What to build
The Sources / Extensions segmented picker in Browse's toolbar no longer collides with or truncates against the trailing buttons on a 375 pt phone (Extensions shows "Update all" plus the repositories button) or at large Dynamic Type. Today it has a fixed `.frame(width: 240)` in the principal slot (`Ahoge/Features/Browse/BrowseView.swift:23-29`).

- Remove the fixed width and let the picker size to its content within the space the toolbar gives it. If it still cannot fit at the largest accessibility sizes, it may move out of the principal slot (for example to a row under the navigation bar) at those sizes only.

## Design direction
- Mode: polish an existing screen.
- Look: inherit. Same segmented `Picker`, same labels, same tint; no new components (DECISIONS: "Existing look and components stay"; "No new dependencies").
- Must not change: the picker's behaviour, the toolbar buttons on either tab, the inline title display.
- Success: on a 375 pt-wide iPhone (iPhone SE 3rd gen / 13 mini sizes) with the Extensions tab and "Update all" visible, nothing overlaps or truncates at the default text size; at the largest non-accessibility Dynamic Type size labels are readable. Verified by the CI simulator build; screenshots are not available in CI, so the report lists the manual check for the user.

## Seams
- No unit seam (layout). CI simulator build compiles the change.

## Reuse first
- `BrowseView` (`Ahoge/Features/Browse/BrowseView.swift`).

## Acceptance criteria
- [ ] No fixed width on the picker.
- [ ] CI build passes.
- [ ] Manual check for the user written in the report (device sizes and Dynamic Type sizes above).
- [ ] Committed with `Part of #12` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Toolbar content of Sources or Extensions.
