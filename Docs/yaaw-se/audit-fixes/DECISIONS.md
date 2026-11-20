# Decisions: audit-fixes

Source: GitHub issues #2-#14 on QuackyPROG/ahoge (bodies are the bug reports; read them with `gh issue view N -R QuackyPROG/ahoge`). All decisions below were accepted by the user on 2026-11-20.

## Process
- Work on branch `fix/audit` with one draft PR to `main`. Push after each ticket; a ticket is done only when CI (`.github/workflows/ios.yml`, test job on pull_request) is green. No Swift toolchain on the dev machine, so CI is the only test runner. Never push to `main` (the phone push script deploys `main`).
- One ticket per root cause; each commit references its issue (`Fixes #N`, closes on merge).
- No new dependencies. Existing look and components stay.
- Every fix gets a regression test at a seam where one exists; UI-only fixes are verified by the CI simulator build (screenshots where possible).

## Navigation (#2)
- Every tab owns `NavigationStack(path: [Route])`; every screen is pushed as a `Route` value. Remove `navigationDestination(item:)` destinations and view-based `NavigationLink { }` pushes to screens containing value links.
- After a migration, the new entry's page replaces the old entry's page and the migrate search (Mihon). When started from More > Migrate, return to that titles list.

## Push script (#3)
- Installs of new commits only inside a quiet window, default 02:00-06:00 local, configurable via `-QuietHours`. `--force` installs immediately. Re-signing still runs at any hour when the 7-day expiry is less than a day away.

## State restoration (#4)
- On cold launch restore the selected tab, the open manga page, and the reader at its chapter and page if it was open. Nothing deeper is restored.

## Reader memory (#5)
- Planner picks exact numbers from Apple guidance within: decoded pages capped at ~4096 px longest side with tall strips sliced; at most previous, current and next chapter kept loaded; caches purged on memory warning.

## Auto-backup (#6)
- Snapshot on main actor, encode/write off main inside a background task assertion, expiration handler set; rotation only touches automatic backups (name pattern or dedicated subfolder).

## Persistence (#7)
- DB open failure: full-screen error with "Retry" and "Share logs" instead of fatalError; on a background launch skip work quietly.
- Failed DB writes are logged and surfaced; ExtensionStore never saves after a failed load and keeps the unreadable file aside.

## Chapter re-keying (#8)
- When a chapter disappears and a new one has the same chapter number (>= 0), carry read state, bookmark, last page, history and download to the new one. With several chapters on one number, also match by scanlator; if still ambiguous, skip the carry-over. Carried chapters do not count as new.
- Orphaned download files are cleaned/re-linked and reindex sweeps orphan folders.

## Reader correctness (#9)
- Stale `loadNext` results after `open()` are dropped; reading clock stops at the start of `open()`.

## Data screens (#10)
- Restore confirmation with "Restore library" (default), "Restore library and settings", "Cancel".
- Clear database "keep" rule also keeps titles with lastPageRead > 0, bookmarks or history; Clear cookies and the wider Clear database get confirmation dialogs in the existing style.
- Remaining #10 items (sourceOrder collisions, category trim, smart interval, migration carrying lastPageRead/history, per-series settings in backup/migration, cleanup of covers/prefs on clear) are fixed.

## iPad / routing (#11)
- Split view vs tabs chosen by device idiom (iPad split view, iPhone always tabs). On iPad all five tab screens stay alive; Updates/History refresh on tab switch instead of on appear.
- Notification taps and deep links dismiss open sheets/reader, then push on top of the Library tab's current path (not replace).

## UI (#12)
- All items in #12 fixed (blank sheets, duplicate ids, fixed widths, stale search field, pinnedOnly re-run).

## Downloads (#13)
- Items 1-3 fixed. Item 4 (background transport races) fixed only if a test can show the race; otherwise left open in #13.

## Minor (#14)
- Fix: Never-update titles on manual refresh, metadata blanking with empty values, Mihon import language mapping.
- Out of scope (architectural, kept open in #14): JS runtime off the main thread; library load off the main thread at launch.

## Round 2 (accepted 2026-11-20)
- Clear database: no new dialog; when the keep toggle is off, the existing "Remove N titles?" message also says read progress, bookmarks and history are deleted. Clear cookies gets a new confirmation.
- Incognito (global or per-source): restoration saves only the selected tab, never the manga page or reader position.
- Push script: the scheduled task does not wake the PC; the script logs that it is waiting for the window; `-QuietHours` moves the window.
- CI: one ticket per CI run, sequential; push and wait for green before starting the next ticket (the workflow cancels in-progress runs on a newer push).
- Planner choices approved: restore state in UserDefaults; reader presented from one place in RootView; automatic backups named `ahoge_auto_…`; image cache 96 MiB, URLCache memory 8 MiB, decoded bitmap max 2048 × 4096 px.
