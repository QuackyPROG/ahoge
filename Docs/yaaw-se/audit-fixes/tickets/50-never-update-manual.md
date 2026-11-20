# 50: Manual library updates skip "Never" titles

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Part of #14

## What to build
A title whose update interval is "Never" is not refreshed by a manual library update (pull to refresh, "Update library", "Update this category"), matching what its page says ("Never checked for new chapters", `Ahoge/Features/Manga/UpdateIntervalRow.swift:37`). Today `UpdatePolicy.decide` returns `.notDue` for interval 0 (`Ahoge/Library/UpdatePolicy.swift:39`) and `LibraryUpdater` lets `.notDue` through on manual runs (`Ahoge/Library/LibraryUpdater.swift:39-42`).

- `SkipReason` gets `.never`, returned for `updateInterval == 0`. Manual runs still override only `.notDue`.
- Refreshing a single title from its own page (pull to refresh in `MangaDetailView`) is unchanged; it does not go through `LibraryUpdater`.

## Design direction
None.

## Seams
- `UpdatePolicyTests`: interval 0 → `.never`; interval 7 within the window → `.notDue`.
- A `LibraryUpdater` test with `SourceFixture` (or a check of the queue filter if it is factored out): a manual update over a Never title and a normal title fetches only the normal one.

## Reuse first
- `UpdatePolicy.decide` (`UpdatePolicy.swift:33-42`), `LibraryUpdater.update` queue filter (`LibraryUpdater.swift:39-42`), existing `UpdatePolicyTests`.

## Acceptance criteria
- [ ] Tests pass in CI.
- [ ] Committed with `Part of #14` in the message (items 4-5 stay open), pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
#14 items 4 and 5 (out of scope).
