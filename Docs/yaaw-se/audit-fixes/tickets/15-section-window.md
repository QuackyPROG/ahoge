# 15: Keep only the previous, current and next chapter loaded

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 14
**Issue:** Part of #5

## What to build
Reading many chapters in a row with "load next chapter" no longer keeps every chapter's pages. Today `loadNext` appends sections (`Ahoge/Features/Reader/ReaderModel.swift:238-240`) and nothing removes them.

- After `loadNext` appends a section, and when `currentChapter` changes in `positionChanged`, `ReaderModel` keeps only the sections of the chapter before the current one, the current one and the one after it (by section order). Sections further back are removed.
- The item on screen keeps its id, so `scrollPosition(id:)` (`ReaderView.swift:317,354`) stays on it. `rebuildItems` (`:268-275`) already follows a moved position.
- The `.start` item of the first remaining section shows the chapter before it, as `buildItems` does today (`:279-281`).
- Pending prefetches for removed sections are dropped (limiter from ticket 12 if merged; otherwise skip this point and note it).

## Design direction
None. Scrolling must not jump when a section far above is removed.

## Seams
- `ReaderModelTests`: chapters 1-5 with 3 pages each (`SourceFixture.extensions(pageCount: 3)`); open 1, then drive `positionChanged` to the end of each chapter so 2, 3, 4 load and the current chapter moves to 3: `sections.map(\.id)` is `["/c/2", "/c/3", "/c/4"]`, and `position` is still an id in `items`.

## Reuse first
- `ReaderModel.loadNext`, `positionChanged`, `rebuildItems` (`ReaderModel.swift:163-192,231-249,268-275`).
- The generation counter from ticket 14.

## Acceptance criteria
- [ ] Never more than 3 sections after any sequence of `loadNext` and position changes (test passes in CI).
- [ ] Existing reader tests pass.
- [ ] Committed with `Part of #5` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Loading the previous chapter when scrolling up (not a feature today).
