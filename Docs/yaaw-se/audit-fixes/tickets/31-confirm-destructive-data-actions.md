# 31: Confirm Clear cookies; name what Clear database deletes

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 30
**Issue:** Part of #10

## What to build
"Clear cookies and website data" asks before it logs the user out of every source. Today it runs on tap (`Ahoge/Features/More/DataStorageView.swift:112-121`).

- **Clear cookies (new confirmation).** A destructive `confirmationDialog`, in the style of `ClearDatabaseView.swift:53-60` and `DataStorageView.swift:146-153`: title "Clear cookies and website data?", message "You will be signed out of every source and website.", destructive button "Clear", then the existing clearing code.
- **Clear database (no new dialog).** Decided in `DECISIONS.md` Round 2. The existing "Remove N titles?" confirmation (`ClearDatabaseView.swift:53-60`) stays the only one. Its message depends on the keep toggle (`keepRead`, or whatever ticket 30 renames it to):
  - Toggle on: unchanged, "Their chapters and history go too. This cannot be undone."
  - Toggle off: "Their chapters, read progress, bookmarks and history go too. This cannot be undone."

## Design direction
None.

## Seams
- No unit seam for dialog presentation; checked by the diff and the CI build. Manual check listed for the user.

## Reuse first
- The confirmation dialogs at `ClearDatabaseView.swift:53-60` and `DataStorageView.swift:146-153`.

## Acceptance criteria
- [ ] Tapping Clear cookies shows the new dialog; Cancel leaves cookies untouched; Clear runs the existing clearing code.
- [ ] Clear database still shows exactly one confirmation; no second dialog is added.
- [ ] With the keep toggle off, the Clear database message names read progress, bookmarks and history; with it on, the message is unchanged.
- [ ] Manual check listed for the user: Clear cookies → Cancel keeps a logged-in source logged in; Clear database with the toggle off shows the longer message.
- [ ] Committed with `Part of #10` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
The keep rule and toggle text (ticket 30).
