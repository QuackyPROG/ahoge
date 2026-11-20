# 13: Reader pages stop holding images they no longer show

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Part of #5

## What to build
A page view the lazy stack keeps alive off screen no longer pins its decoded image. Today `ReaderPageView` holds the image in `@State` (`Ahoge/Features/Reader/ReaderPageView.swift:23`) from load (`:90`) for as long as the view lives, so the cache's evictions free nothing.

- On disappear the view sets its image to nil (and `loadedKey` to nil). On appear it takes the image from `ImageMemoryCache` if there, otherwise loads again through the existing `.task`.
- The placeholder keeps the known aspect ratio (`PageAspect.known`, `:124`) so the strip does not jump when an image is released and comes back.
- Paged mode (`ZoomableImage`) gets the same release; the visible page is never released while on screen.

## Design direction
None. The look on screen must not change: no flash on scroll back when the image is still cached (first-frame cache read in `init`, `:46-51`, stays).

## Seams
- No unit seam for SwiftUI view state. The ticket is checked by reading the diff and by the CI simulator build. The report lists a manual check for the user: scroll a long webtoon down and back up; pages reappear without layout jumps.

## Reuse first
- `ReaderPageView`'s cache read in `init` and its `.task(id:)` load (`ReaderPageView.swift:46-51,81-95`), `PageAspect` (`:5-9`).

## Acceptance criteria
- [ ] `ReaderPageView` clears its image state on disappear and restores it from cache or reloads on appear.
- [ ] CI build and existing tests pass.
- [ ] Committed with `Part of #5` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Slicing tall strips (ticket 16).
