# 17: Stop the reading clock when another chapter opens

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 14
**Issue:** Fixes #9

## What to build
Time spent in a chapter opened with Previous/Next or the chapter list is credited to that chapter, not the one before. Today `open()` changes `currentChapter` while `ready == false`, so `restartClock` is skipped (`ReaderView.swift:131-133`), and `startClock` returns early because `clockSince != nil` (`ReaderModel.swift:204-207`).

- The clock stops (saving the old chapter's time) at the start of `open()`. `open()` needs the repository for that: pass `repo` to `open` or call `stopClock(repo:)` from every `open` call site in `ReaderView` (`:124,175,192` and the error retry at `:79`) before `open`. Pick one and use it everywhere.
- When the new chapter is ready, `startClock` runs as today (`ReaderView.swift:128-130`) and now starts, because the clock was stopped.

## Design direction
None.

## Seams
- `ReaderModelTests` with `LibraryRepository.inMemory()` and `SourceFixture`: open chapter 1, `startClock(now: t0)`, open chapter 2 at `t0 + 60` (stopping as implemented), `startClock(now: t0 + 60)`, `stopClock(repo:, now: t0 + 90)`: history `timeRead` is 60 for chapter 1 and 30 for chapter 2 (read through `repo.historyByChapter()`).

## Reuse first
- `startClock`, `stopClock`, `restartClock` (`Ahoge/Features/Reader/ReaderModel.swift:204-223`), `LibraryRepository.historyByChapter()` (`Ahoge/Library/LibraryRepository+Backup.swift:32-42`).

## Acceptance criteria
- [ ] The test passes in CI.
- [ ] Every path that opens a chapter stops the clock first (listed in the report).
- [ ] Committed with `Fixes #9` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
The stale `loadNext` result (ticket 14).
