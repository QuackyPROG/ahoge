# 01 — Webtoon pages decode once, at screen width

- **Status:** in-progress
- **Blocked by:** none
- **Change type:** logic
- **Model:** sonnet  <!-- 4 files plus tests, and cache keys several call sites share -->

## Goal
In webtoon mode, every page is loaded through the slice path from its first load, so a tall page is decoded once and never re-laid out from one item into slices with new cache keys. Webtoon pages are decoded at the current screen width in pixels (capped at 2048) instead of 2048 px. Fixes #16.

## Files
- modify: `Ahoge/Services/ImageLoader.swift`
- modify: `Ahoge/Features/Reader/PageGeometry.swift`
- modify: `Ahoge/Features/Reader/ReaderModel.swift`
- modify: `Ahoge/Features/Reader/ReaderPageView.swift`
- modify: `Ahoge/Features/Reader/ReaderView.swift`
- modify: `Tests/AhogeTests/ImageLoaderTests.swift`
- modify: `Tests/AhogeTests/PageGeometryTests.swift`
- modify: `Tests/AhogeTests/ReaderModelTests.swift`

## Interfaces
```swift
// ImageLoader — width joins the slice key; at 2048 the key is unchanged from today.
nonisolated static func sliceKey(_ url: String, _ index: Int, maxPixelWidth: CGFloat = ImageLoader.maxPixelWidth, transform: ImageTransform = .plain) -> String
// = cacheKey(url, maxPixelWidth: maxPixelWidth, transform: transform) + "#s\(index)"

func slice(_ index: Int, of url: String, headers: [String: String] = [:], maxPixelWidth: CGFloat = ImageLoader.maxPixelWidth,
           transform: ImageTransform = .plain, priority: TaskPriority = .userInitiated) async throws -> UIImage
// Also records the page's size: ImageMemoryCache.shared.recordSize(pixelSize(data, maxPixelWidth: ImageLoader.maxPixelWidth), for: url)
// (same key and same 2048 basis as image() uses today, so onSize/learnSize keep working).

// PageGeometry
static func sliceCount(_ size: CGSize, maxPixelWidth: CGFloat = ImageLoader.maxPixelWidth) -> Int
// height * min(1, maxPixelWidth / width), in pieces of at most ImageLoader.maxPixelLength.

// ReaderModel.Layout
var webtoonWidth: CGFloat = ImageLoader.maxPixelWidth   // decode width in pixels for webtoon mode

// ReaderPageView init gains:
decodeWidth: CGFloat = ImageLoader.maxPixelWidth
```

## Steps
1. Write the failing tests first:
   - `PageGeometryTests`: `sliceCount(800×20000)` is 5 (unchanged); `sliceCount(2048×20000, maxPixelWidth: 1179)` is 3; `sliceCount(800×3000, maxPixelWidth: 1179)` is 1.
   - `ImageLoaderTests`: `sliceKey(url, 0)` equals today's `cacheKey(url, maxPixelWidth: 2048) + "#s0"`; `sliceKey(url, 0, maxPixelWidth: 1179)` differs from it. Write an 800 × 20000 PNG to a temporary file URL, call `ImageLoader.shared.slice(0, of: fileURL, maxPixelWidth: 400)`: the result is 400 px wide and at most 4096 tall, `ImageMemoryCache.shared.size(of: fileURL)` is 800 × 20000, and slices 1… are already in the cache under `sliceKey(…, maxPixelWidth: 400)`. A short 800 × 1000 PNG gives 1 slice of 400 × 500.
   - `ReaderModelTests`: with `Layout(sliceTall: true)` and no size learned, every page item has `slice == 0` and keeps its page id. After `learnSize(800×20000)` for page 0, the first item still has the page id and `slice == 0`, followed by slices 1…4. With `webtoonWidth: 1179` and `learnSize(2048×20000)`, page 0 has 3 slices.
2. `ImageLoader`: add the width to `sliceKey` and `slice` as above, and use it for the slicing task's dedupe key and the cache inserts. In `slice`, record the page's size from the fetched data. In `slices`, when there is one slice that covers the whole strip and no crop, use the strip as it is instead of copying it with `ownBitmap`.
3. `PageGeometry.sliceCount`: take `maxPixelWidth` as above.
4. `ReaderModel`: add `Layout.webtoonWidth`. In `pageItems`, when `layout.sliceTall` is on, a page whose size is unknown or that has 1 slice gets `slice = 0`; tall pages use `PageGeometry.sliceCount(size, maxPixelWidth: layout.webtoonWidth)`. `prefetch` passes `layout.webtoonWidth` to `ImageLoader.slice` when it has a slice.
5. `ReaderPageView`: take `decodeWidth`; use it in `cacheKey` (slice path) and pass it to `ImageLoader.slice`. The non-slice path is unchanged.
6. `ReaderView`: store the reader's width in points from the existing background `GeometryReader` next to `isLandscape`, read `@Environment(\.displayScale)`, and set `layout.webtoonWidth = min(ImageLoader.maxPixelWidth, (width * displayScale).rounded(.up))` in webtoon mode (2048 otherwise). Pass it to `ReaderPageView` as `decodeWidth` for webtoon items. `currentImage` (the share button) in webtoon mode reads `sliceKey(url, 0, maxPixelWidth: layout.webtoonWidth, transform:)` first, so the share button does not disappear now that webtoon pages are always slices.

## Done when
- [ ] The new and existing tests in `ImageLoaderTests`, `PageGeometryTests` and `ReaderModelTests` pass in the CI `test` job (`.github/workflows/ios.yml`, macOS runner), with the run URL in the report. No local Swift toolchain is available on Windows.
- [ ] The CI build compiles with no new warnings in the changed files.
- [ ] `ImageMemoryCache`'s 96 MiB limit and its test are unchanged.

## User checks
- On device, open a streamed webtoon chapter with tall pages and scroll down steadily: the stutter as the next page arrives is gone or clearly smaller than before.
- Rotate the phone in webtoon mode: pages reload once and stay sharp.
- In webtoon mode, the share button in the top bar still appears and shares the page.
- Paged modes (left to right, right to left, vertical) look and zoom as before.

## Do not
- Add dependencies.
- Touch files not listed above.
- Change `ImageMemoryCache`'s cost limit, `ImageLoader.maxPixelWidth`, `maxPixelLength` or the paged-mode decode path.
- Fix the existing `trimSections` key mismatch for slice prefetches; that is out of scope.
- Add a debug counter or logging (the user tests by feel, Q3).

## Context
- Decisions: `docs/plans/reader-scroll-stutter/DECISIONS.md` (Q6 scope, Q7 width).
- Slicing came from audit ticket 16: `Docs/yaaw-se/audit-fixes/tickets/16-decode-cap-and-slices.md`.
- Issue: https://github.com/QuackyPROG/ahoge/issues/16
