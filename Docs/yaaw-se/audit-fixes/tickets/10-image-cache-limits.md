# 10: Lower image cache limits and purge on memory warning

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Part of #5

## What to build
The app gives memory back when iOS asks, and its image caches hold less.

- `ImageMemoryCache.totalCostLimit` (`Ahoge/Services/ImageLoader.swift:11`): 200 MiB → 96 MiB (`96 << 20`).
- `ImageLoader`'s `URLCache` memory capacity (`ImageLoader.swift:36`): 50 MiB → 8 MiB. Disk stays 500 MiB.
- On `UIApplication.didReceiveMemoryWarningNotification`: `ImageMemoryCache.removeAll()`, URLCache memory purged without touching its disk cache (for example set `memoryCapacity` to 0, then back to 8 MiB), and `PageAspect`'s dictionary is left alone (it is tiny). The observer is registered once, at `ImageMemoryCache` creation or app start.
- Apple, "Responding to memory warnings" (checked 2026-11-20): "Remove references to images, media files, or any large data files that already have an on-disk representation and can be reloaded later."

## Design direction
None.

## Seams
- `ImageLoaderTests`: insert an image into `ImageMemoryCache.shared`, post `UIApplication.didReceiveMemoryWarningNotification` on `NotificationCenter.default`, the entry is gone. A test reads the cost limit through a small internal accessor and checks 96 MiB.

## Reuse first
- `ImageMemoryCache.removeAll()` (`ImageLoader.swift:20`), `ImageLoader.clear()` (`:98-101`) as the model for the purge.

## Acceptance criteria
- [ ] Limits are 96 MiB decoded and 8 MiB URLCache memory.
- [ ] Memory-warning test passes in CI.
- [ ] Committed with `Part of #5` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Cancelling prefetches on a warning (ticket 12), the decode cap (ticket 16).
