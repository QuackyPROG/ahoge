# Decisions: reader-scroll-stutter

## Request
write an issue and investigate a problem about reading stutters when scrolling down... its not smooth at all..

Issue: https://github.com/QuackyPROG/ahoge/issues/16

## Settled
- Fact (Verified, project.yml / Package.swift): iOS 17.0 deployment target, SwiftUI.
- Fact (Verified, ImageLoader.swift:12, ImageLoaderTests): decoded-image cache is 96 MiB; a test pins it.
- Fact (Verified, git log e7e6a52, Docs/yaaw-se/audit-fixes/tickets/10 and 16): the cache was lowered from 200 MiB to 96 MiB and pages were capped at 2048 × 4096 px for memory (issue #5), during the audit fixes.
- Fact (Verified, ReaderModel.swift:187): webtoon and paged both prefetch 5 items ahead (1 on cellular with "Preload only on Wi-Fi").
- Fact (Verified, ReaderPageView.swift:69-73): webtoon pages have no zoom; paged pages use ZoomableImage.
- Fact (Verified, memory note + platform): builds go through xtool on Windows/WSL, so Instruments (macOS only) is not available for profiling.

- Q1 Where it stutters: webtoon mode. Downloaded or streamed is not answered yet (follow-up Q4).
- Q2 When it started: it was there before the audit fixes, but is more noticeable since. Treated as an older problem made worse by the audit changes.
- User observation (round 1): the frame rate is fine while scrolling; the stutter happens when the next page loads.
- Fact (Verified, ReaderModel.swift:280-295, 345-393; ReaderPageView.swift:88-106): a tall webtoon page whose size is not yet known is loaded whole first (`slice` nil, downscaled to 4096 px on its long side). Only then does `learnSize` rebuild it into slice items, which have different cache keys, so each slice is fetched and decoded again. The first decode is thrown away, and the item list changes while the page is near the screen. Slicing came in with audit ticket 16, which fits "more noticeable now". (Inferred: this is the main cause.)
- Fact (Verified, ReaderPageView.swift:8, 152): a page or slice not loaded yet is drawn at a guessed aspect of 0.7 unless seen before; a 2048 × 4096 slice is 0.5, so its height changes when it loads.

- Q3 How the fix is confirmed: the user tests it by feel on device after the build is pushed. No debug counter. (rejected: temporary hitch/decode counter)
- Q4 Downloaded or streamed: streamed chapters (user wrote "streaming, now downloaded", read as "not downloaded").
- Q5 What the stutter looks like: a short stutter while the next page loads; not a freeze and not a content jump. (rejected: freeze, jump, placeholder pop-in)
- Fact (Verified, ImageLoader.swift:121-145): `ImageLoader.slice` never calls `recordSize`, so a page loaded only through slices does not report its size.

- Q6 Fix scope: both (A) load every webtoon page through the slice path from the start, recording its size, and (B) decode webtoon pages at screen width instead of 2048 px. (rejected: A only; A now and B if needed, which was recommended)
- Fact (Verified, gh: PR 15 merged; git log origin/main..fix/audit): the audit fixes are on main; `fix/audit` has 1 extra commit (4fb3b74). The feature branch is cut from origin/main.

- Q7 Decode width for webtoon pages: the current screen width in pixels (points × scale), capped at 2048; rotating reloads pages once. Webtoon side padding does not reduce it. (rejected: shorter screen side)

## Open
