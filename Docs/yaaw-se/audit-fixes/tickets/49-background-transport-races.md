# 49: Background transport races, only if a test can show them

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 46, 47, 48
**Issue:** Fixes #13 if fixed; otherwise a comment on #13

## What to build
Decision: item 4 of #13 is fixed only if a test can show the race; otherwise it stays open. Two suspected races in `Ahoge/Downloads/BackgroundTransport.swift`:
- Cancellation before `waiting[id]` is set (`:34-45`) may leak the continuation and hang that download worker.
- `urlSessionDidFinishEvents` (`:68-75`) may run before `setEventsCompletionHandler` (`:30-32`, called from `AppDelegate.swift:22-28`), so the handler is never called.

Steps:
1. Try to write a failing test for each. The delegate methods can be called directly on the shared instance with fake tasks only if the code is first made testable without a real background session (for example a factory for the session and task, test-only init). That refactor is allowed only together with a test that fails before the fix.
2. For each race a test shows: fix it (resume the continuation with `CancellationError` when cancelled before registration; remember that events finished and call a handler set later), keep the test.
3. For a race no test can show: change nothing in the code; add a comment on #13 with `gh issue comment 13 -R QuackyPROG/ahoge` saying what was tried and why it could not be shown.

## Design direction
None.

## Seams
- `BackgroundTransport` delegate methods driven directly in a unit test, if step 1 succeeds. Background `URLSession` itself cannot run in the simulator test host reliably (**Unknown**; the agent states what it found).

## Reuse first
- `BackgroundTransport` (`Ahoge/Downloads/BackgroundTransport.swift`), `AppDelegate.application(_:handleEventsForBackgroundURLSession:completionHandler:)`.

## Acceptance criteria
- [ ] Each race is either fixed with a test that fails before the fix, or untouched with a comment on #13 (comment URL in the report).
- [ ] The commit uses `Fixes #13` only when both races are fixed; otherwise `Part of #13`, and #13 stays open. With nothing to commit, the report says so and no commit is made.
- [ ] If committed: pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Other background download behaviour.
