# 02 — Upright pages and the webtoon width from the first frame

- **Status:** in-progress
- **Blocked by:** 01
- **Change type:** logic
- **Model:** sonnet  <!-- ImageIO orientation handling and a SwiftUI timing fix -->

## Goal
Webtoon pages with an EXIF orientation tag show upright again, and webtoon pages are never decoded at 2048 px before the reader's width is measured. These are the 2 medium findings from ticket 01's reviews. Part of #16.

## Files
- modify: `Ahoge/Services/ImageLoader.swift`
- modify: `Ahoge/Features/Reader/ReaderView.swift`
- modify: `Tests/AhogeTests/ImageLoaderTests.swift`

## Interfaces
```swift
// Unchanged signature; new guarantee: the returned UIImage has imageOrientation == .up and its
// cgImage holds the pixels upright, whatever the file's EXIF orientation.
nonisolated static func decode(_ data: Data, maxPixelWidth: CGFloat, maxPixelLength: CGFloat = ImageLoader.maxPixelLength) -> UIImage?
```

## Steps
1. Write the failing tests first in `ImageLoaderTests`. Build a JPEG of 100 × 200 raw pixels with EXIF orientation 6 (`CGImageDestination` with `kCGImagePropertyOrientation: 6`; the image turns a quarter turn, so it shows 200 × 100). Then:
   - `ImageLoader.decode(data, maxPixelWidth: 2048)` has `imageOrientation == .up` and a `cgImage` 200 wide and 100 tall.
   - `ImageLoader.slices(data, maxPixelWidth: 2048)` gives 1 slice whose `cgImage` is 200 × 100.
   - `ImageLoader.pixelSize(data, maxPixelWidth: 2048)` is 200 × 100 (it already swaps; this pins it next to the decode).
   - Also tighten 2 weak tests from ticket 01: `testShortPageIsOneSlice` must check the specific error (`URLError(.cannotDecodeContentData)`) for slice 1, not any error, and the slices-cached test checks every slice from 1 to the last (`1..<5` for the 800 × 20000 page), not only 1 and 2.
2. `ImageLoader.decode`: take the `UIImage(data:)` fast path only when the image fits the limits **and** its EXIF orientation is 1 or absent (read `kCGImagePropertyOrientation` from the same properties `pixelSize(of:)` reads). Any other orientation goes through the thumbnail path, which already draws the pixels upright (`kCGImageSourceCreateThumbnailWithTransform`), with the thumbnail size set to the image's longest side, so it is not shrunk.
3. `ReaderView.webtoonWidth`: when `readerWidth` is still 0, use the current screen's width (the existing `screen` property, `screen.bounds.width`) instead of returning 2048. Return 2048 only when neither is known. Keep `min(ImageLoader.maxPixelWidth, (width * displayScale).rounded(.up))`.
4. `ReaderView.currentImage`: use the `transform` constant in the fallback line instead of calling `pageTransform(paged:)` again, and move the "With a transform on, only the transformed copy is cached." comment down to that line.

## Done when
- [ ] The new and existing tests pass in the CI `test` job (`.github/workflows/ios.yml`, run by hand with `gh workflow run ios.yml --ref yaaw/reader-scroll-stutter`), with the run URL in the report.
- [ ] The CI `ipa` job builds.
- [ ] Before the fix, the orientation tests fail: report the reason they fail by reading the code, as they cannot run locally (no Swift toolchain on Windows).

## User checks
- Open a webtoon chapter: the first pages appear without loading twice (no second placeholder or fade on the first screen).
- The webtoon pages still look right side up and sharp.

## Do not
- Add dependencies.
- Touch files not listed above.
- Change the paged-mode decode width, the cache limit or `reposition()` (the blank flash on resize is a low finding, left as is).
- Draw images on the main thread.

## Context
- Final review finding 1 (orientation) and ticket review finding 1 (width before measuring), recorded in `Docs/plans/reader-scroll-stutter/RUNLOG.md`.
- Ticket 01: `Docs/plans/reader-scroll-stutter/tickets/01-webtoon-single-decode-at-screen-width.md`.
