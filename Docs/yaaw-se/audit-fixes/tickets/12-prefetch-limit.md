# 12: At most two prefetch decodes at once

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Part of #5

## What to build
Reader prefetching no longer starts an unbounded number of detached decodes. Today every position change starts up to 5 tasks (`ReaderModel.swift:176-179`) and every new chapter 3 (`:241-244`), each a detached decode, with no limit across them.

- A small limiter (an actor or a serial queue of pending requests) lets at most **2** prefetch decodes run at once. Requests beyond that wait in order; a request for a page that is already pending is not added twice.
- When the reader closes (`ReaderModel` deinit or an explicit `cancelPrefetches()` called from `ReaderView`'s disappear) pending prefetches are dropped.
- On `UIApplication.didReceiveMemoryWarningNotification`, pending prefetches are dropped.
- The look-ahead counts stay as they are (5, 3, and 1 on cellular with "Preload only on Wi-Fi").
- Apple, "Responding to memory warnings" (2026-11-20): "restrict the number of simultaneous operations that your app performs."

## Design direction
None.

## Seams
- Unit test on the limiter alone (`ReaderModelTests.swift` or a new `PrefetchLimiterTests.swift`): enqueue 6 jobs whose bodies wait on a continuation and record how many run at once; the maximum is 2; a duplicate key is not run twice; `cancelAll()` drops the waiting ones.

## Reuse first
- `ReaderModel.prefetch` (`Ahoge/Features/Reader/ReaderModel.swift:252-259`), `ImageLoader.prefetch` (`Ahoge/Services/ImageLoader.swift:91-93`).

## Acceptance criteria
- [ ] All reader prefetches go through the limiter (`ImageLoader.prefetch` and `ReaderModel.prefetch` both use it).
- [ ] Limiter tests pass in CI.
- [ ] Committed with `Part of #5` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Dropping far sections (ticket 15).
