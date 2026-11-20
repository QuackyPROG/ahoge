# Run log: reader-scroll-stutter

Times are local, `YYYY-MM-DD HH:MM`. One row per stage or ticket attempt.

| Item | Model | Start | End | Minutes | Result | Notes |
|---|---|---|---|---|---|---|
| 01 | sonnet | 2026-11-20 20:41 | 2026-11-20 21:00 | 19 | done | 1 fix round (loadNext prefetch skipped the slice path). Tests run only in CI (no Swift toolchain on Windows): run 44738672955, 362 tests, 0 failures. VERIFY partial (no local probes; test-target warnings not in the log). Review: 1 medium (webtoonWidth is 2048 until the reader width is measured, so the first pages may decode at 2048 then again at screen width). Weak tests: testShortPageIsOneSlice catch-all; slices cached only checked for 1-2; no test for the prefetch width, the loadNext slice or the currentImage lookup. |
| 02 | sonnet | 2026-11-20 21:50 | | | | |

## Summary
- Total time: 19 min (ticket 01 only; interrogate and plan not timed)
- Slowest items: 01 (waiting on CI, about 8 min, as tests cannot run on Windows)
- Escalations: none
- Final review (opus): 2 medium (EXIF orientation lost on single-slice webtoon pages; first pages may decode at 2048 before the width is measured), 2 low (reposition flash on resize; duplicate transform in currentImage).
