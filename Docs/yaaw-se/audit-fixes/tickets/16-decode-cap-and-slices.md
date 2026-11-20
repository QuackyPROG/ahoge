# 16: Cap decoded pages at 4096 px and slice tall webtoon strips

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 10, 11, 12, 13, 15
**Issue:** Fixes #5

## What to build
No decoded page bitmap is longer than 4096 px on its longest side, so one page costs at most 2048 × 4096 × 4 B = 32 MiB. Today pages up to 2048 px wide are decoded at full height (`Ahoge/Services/ImageLoader.swift:115-120`): an 800 × 20000 strip is about 64 MB, a 4000 × 60000 strip about 250 MB.

- **Decode.** `ImageLoader.decode` gains a longest-side limit of 4096 px. Covers and other small decodes are unchanged (they already pass a small `maxPixelWidth`).
- **Webtoon mode.** A page whose height after width scaling (to at most `ImageLoader.maxPixelWidth`, 2048) is over 4096 px becomes consecutive slice items of at most 4096 px each, top to bottom. Build them like the split-wide halves in `ReaderModel.pageItems` (`Ahoge/Features/Reader/ReaderModel.swift:301-338`): one item per slice, with `pageIDs` on the first slice only, so progress, `itemID(containing:)` and page numbers still count whole pages. The page's size comes from `learnSize` (`:155-160`), so items rebuild once it is known; rebuild for tall pages in webtoon mode as well as for wide pages.
- **Slice decoding.** `ImageLoader` decodes a slice by downsampling the page to the width limit and cropping the slice's rows, caching each slice under its own key (URL plus slice index). The full downsampled strip is not cached. Its transient size is bounded by the width limit; tickets 11-12 keep decodes to two at a time.
- **Paged modes.** The whole page is scaled to fit 4096 px on its longest side; no slices.
- `ReaderPageView` shows one slice per item in webtoon mode; `PageAspect` uses the slice's aspect.

## Design direction
None. A sliced strip must look continuous: no gap between slices of the same page, whatever the webtoon gap setting (the gap goes between pages only).

## Seams
- `ImageLoaderTests` (existing `testTallStripKeepsItsWidthLimit` is updated): an 800 × 20000 PNG decodes to at most 4096 px tall in paged mode; the same strip in webtoon mode has 5 slices, 800 × 4096 for slices 0-3 and 800 × 3616 for slice 4; a 4000 × 60000 image's slices are at most 2048 × 4096. Build test images with `UIGraphicsImageRenderer` at scale 1, as `EntryScreenTests.swift:15-21` does.
- `ReaderModelTests`: with webtoon layout and a learned size of 800 × 20000 for page 0, the chapter's items for that page are 5 slice items, and `itemID(containing: pageID(url, 0))` is the first slice.

## Reuse first
- `ImageLoader.decode` (`ImageLoader.swift:105-129`), `ImageLoader.cacheKey` (`:44-46`).
- Split-wide item building and `learnSize` in `ReaderModel` (`ReaderModel.swift:155-160,301-338`), `PageGeometry` (`Ahoge/Features/Reader/PageGeometry.swift`).

## Acceptance criteria
- [ ] No reader decode returns an image longer than 4096 px (tests pass in CI).
- [ ] Tall strips are sliced in webtoon mode; paged modes are capped without slices.
- [ ] Reading progress, page numbers and "last page read" still count whole pages (existing reader tests plus the new one pass).
- [ ] Manual check listed for the user: a long webtoon chapter scrolls without visible seams; memory in Xcode's gauge stays bounded across 5 chapters.
- [ ] Committed with `Fixes #5` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Region decoding without a transient strip bitmap (not available in ImageIO). Changing the 2048 px width limit.
