# 14: Drop stale "load next chapter" results after a chapter jump

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Part of #9

## What to build
Tapping "Previous chapter" or jumping in the chapter list near the end of a chapter no longer appends the old "next" chapter after the newly opened one, so the wrong chapter is never shown or marked read, and a stale error never lands on the new chapter.

Repro from #9: within 3 pages of the end of chapter 5 (prefetch of 6 started), tap Previous chapter. Today the reader shows 4 followed by 6.

- `ReaderModel` gets a generation counter, bumped at the start of `open()` (`Ahoge/Features/Reader/ReaderModel.swift:99`). `loadNext` (`:231-249`) captures it before its `await` and, after the `await`, drops both the pages and the error when it changed. `isLoadingNext` is reset either way.
- **New test seam.** `PageProvider` (`Ahoge/Downloads/PageProvider.swift`) gets an injectable remote lookup: a stored closure `(ChapterRecord) async throws -> [SourcePage]` that defaults to today's `sources.source(id).pages(url:)`. Downloads still come first. The test adapter is a gate that suspends a chosen chapter's lookup until the test releases it.

## Design direction
None.

## Seams
- `ReaderModelTests`: a manga with chapters 4, 5, 6 (`SourceFixture.manga(in:chapters: 6)`), a `PageProvider` whose lookup for chapter 6 waits on a gate. Open chapter 5, move `position` to its last page so `loadNext` starts for 6, call `open(chapter 4)` and await it, release the gate, wait until `isLoadingNext` is false: `sections.map(\.id)` is `["/c/4"]` and `error` is nil. Same with the gate throwing: `error` stays nil.

## Reuse first
- Generation-token pattern in `SourceBrowseModel.loadMore` (`Ahoge/Features/Browse/SourceBrowseView.swift:82-93`).
- `SourceFixture` (`Tests/AhogeTests/Support/SourceFixture.swift`), `PageProviderTests` setup (`Tests/AhogeTests/PageProviderTests.swift:7-20`).

## Acceptance criteria
- [ ] Both test cases pass in CI, and fail without the generation check (say so in the report; the agent cannot run them locally, so it states the reasoning).
- [ ] `PageProviderTests` still pass.
- [ ] Committed with `Part of #9` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
The reading clock (ticket 17). Dropping far sections (ticket 15).
