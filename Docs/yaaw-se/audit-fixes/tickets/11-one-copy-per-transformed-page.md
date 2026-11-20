# 11: Keep one decoded copy per page when a transform is on

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 10
**Issue:** Part of #5

## What to build
With crop borders, grayscale, invert, split or rotate on, a page costs one decoded bitmap in memory, not two. Today `ImageLoader.image` (`Ahoge/Services/ImageLoader.swift:53-58`) caches the plain decode and the transformed copy. (The issue's `ImageTransform.swift:236-247` reference is wrong; that file has 67 lines.)

- When the transform is not identity, the plain base is decoded but not left in `ImageMemoryCache` after the transformed copy is made. A concurrent caller asking for the plain page still shares the in-flight task.
- The untransformed size is still available for wide-page detection. Today `ReaderPageView` (`ReaderPageView.swift:83,89`) reads it from the plain cache entry. Record the size separately (a small thread-safe size map keyed by URL next to `ImageMemoryCache`, or return it with the image) and use that in `ReaderPageView` and `ReaderModel.prefetch` (`ReaderModel.swift:252-259`).
- A split page's two halves still come from one base decode when both halves are requested close together (the in-flight task is shared); a later request may decode again, which is acceptable.

## Design direction
None.

## Seams
- `ImageLoaderTests` with a local file URL (write a PNG to a temp file; `ImageLoader.image` reads file URLs without the network): requesting it with `ImageTransform(grayscale: true)` leaves the transformed key in `ImageMemoryCache` and not the plain key; the recorded untransformed size equals the PNG's size.

## Reuse first
- `ImageLoader.cacheKey` (`ImageLoader.swift:44-46`), `ImageTransform.isIdentity` and `cacheSuffix` (`Ahoge/Features/Reader/ImageTransform.swift:23-35`).

## Acceptance criteria
- [ ] With a transform, only the transformed key is cached (test passes in CI).
- [ ] Wide-page split and spreads still learn sizes (existing `PageGeometryTests`, `PagePairingTests` pass).
- [ ] Committed with `Part of #5` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Prefetch limits (ticket 12), slices (ticket 16).
