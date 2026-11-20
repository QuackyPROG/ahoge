format: 1
stage: build
feature: Fix the bugs from the 2026 code audit, GitHub issues #2-#14

## Tickets
- [ ] 01: Push script installs only inside a quiet window
- [ ] 02: Every tab owns a Route path in AppNavigator
- [ ] 03: Browse pushes Global search, Open link and Extension details as routes
- [ ] 04: Manga page pushes "Search all sources" and Migrate as routes
- [ ] 05: More > Migrate screens become routes
- [ ] 06: Updates > Upcoming is a route
- [ ] 07: A finished migration replaces the old page and the migrate search
- [ ] 08: The reader is presented from one place
- [ ] 09: Restore the tab, manga page and reader on a cold launch
- [ ] 10: Lower image cache limits and purge on memory warning
- [ ] 11: Keep one decoded copy per page when a transform is on
- [ ] 12: At most two prefetch decodes at once
- [ ] 13: Reader pages stop holding images they no longer show
- [ ] 14: Drop stale "load next chapter" results after a chapter jump
- [ ] 15: Keep only the previous, current and next chapter loaded
- [ ] 16: Cap decoded pages at 4096 px and slice tall webtoon strips
- [ ] 17: Stop the reading clock when another chapter opens
- [ ] 18: Choose split view or tabs by device, not size class
- [ ] 19: iPad sidebar keeps every tab's screens alive
- [ ] 20: Notification taps and deep links dismiss covers, then push on Library
- [ ] 21: Auto-backup encodes and writes off the main thread under a background task
- [ ] 22: Rotation deletes only automatic backups
- [ ] 23: Show an error screen instead of crashing when the database cannot open
- [ ] 24: Log and show failed database writes
- [ ] 25: ExtensionStore never overwrites an unreadable state file
- [ ] 26: Carry chapter state when a chapter's URL changes
- [ ] 27: Re-link or delete downloads of re-keyed and removed chapters
- [ ] 28: Reindex deletes download folders that match no chapter
- [ ] 29: Restore asks first and leaves settings alone by default
- [ ] 30: Clear database keeps titles with any progress, bookmark or history
- [ ] 31: Confirm Clear cookies; name what Clear database deletes
- [ ] 32: Restored chapters get unique source order
- [ ] 33: Restore matches category names trimmed
- [ ] 34: Restore keeps an existing title's Smart update interval
- [ ] 35: Migration carries last page read and history
- [ ] 36: Per-series reader settings go into backups and migrations
- [ ] 37: Clear database removes cleared titles' covers and settings
- [ ] 38: The migrate sheet is never blank
- [ ] 39: Global search shows each result once
- [ ] 40: Source browse de-duplicates within one page
- [ ] 41: Repeating genre tags and options get unique ForEach ids
- [ ] 42: Browse picker fits narrow phones and large text
- [ ] 43: Manga page details pane is not a fixed 400 pt
- [ ] 44: Sources' search field resets after a search
- [ ] 45: "Pinned only" re-runs only the screen it is toggled on
- [ ] 46: Opening a CBZ download unpacks it off the main thread
- [ ] 47: A resumed download keeps only pages saved for the same page list
- [ ] 48: Cancelling while a chapter is zipped leaves nothing behind
- [ ] 49: Background transport races, only if a test can show them
- [ ] 50: Manual library updates skip "Never" titles
- [ ] 51: Metadata refresh keeps fields the source returns empty
- [ ] 52: Mihon import picks the source language from the source id

## Log
- 2026-11-20 15:29: started; audit filed as issues #2-#14 (QuackyPROG/ahoge)
- 2026-11-20 15:40: probe done, user accepted all 12 recommendations; DECISIONS.md written; branch fix/audit; stage plan
- 2026-11-20 16:20: planner wrote SPEC.md and 52 tickets; 3 open questions (blocks 09, 31)
- 2026-11-20 16:35: round-2 answers accepted (Q1-Q5 yes); re-dispatching planner to close open questions
- 2026-11-20 16:50: spec has no open questions; user approved 52 tickets; stage build
