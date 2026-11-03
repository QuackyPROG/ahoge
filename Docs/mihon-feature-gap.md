# Mihon → Ahoge feature gap

Compared against Mihon `main` @ `e588e04` (2026-10-26) and Ahoge 0.3.0 (`f3044d7`).
The Mihon list comes from its actual settings and screen labels, not from memory.

**Rating:** ★★★ core, users will miss it · ★★ clearly worth it · ★ niche · ✗ doesn't fit iOS or Ahoge

## What Ahoge already has (parity)

- Browse: JS extension repos (add/remove, uninstall-with-repo), install/update/uninstall, sources grouped by language, Popular/Latest, search, source filters, WebView fallback, clear cookies/website data
- Library: category tabs with swipe, create/rename/reorder/delete, default category (or always ask), tri-state set-categories sheet, multi-select (categories, read/unread, remove), sort (title, date added, last read, unread), search, manual library update with progress
- Manga screen: Mihon-style header, description, status, genre chips, Resume/Start button, pull to refresh, chapter sort/filter, fast scroll, swipe and context actions, mark previous as read, multi-select, copy title, open in WebView
- Reader: webtoon, paged LTR/RTL/vertical, per-series mode + "use for new series", tap zones + invert, pinch/double-tap zoom, page slider, chapter transitions, chapter list, background colour, page number, keep screen on, dim, webtoon padding and gap, share page
- Updates (by day, badge), History (last read per series, resume, remove, clear, search)
- Appearance: Mihon palettes, theme mode, pure black

---

## 1. Downloads and offline reading (biggest gap)

| Feature | What it does in Mihon | Rating |
|---|---|---|
| Download chapters | Download one, many, or all chapters from the manga screen, Updates, or reader. Read offline. | ★★★ |
| Download queue | Screen with progress, pause/resume, reorder, cancel. | ★★★ (needed once downloads exist) |
| Downloaded indicator | Icon on chapter rows; "Downloaded" filter in manga screen, Library, and Updates. | ★★★ |
| Delete downloads | Per-chapter, bulk, and "Delete downloaded chapters?" when removing from library. | ★★★ |
| Auto-delete after reading | Delete when marked read manually, or the Nth-to-last read chapter after reading. Option to keep bookmarked chapters. | ★★ |
| Download new chapters | Auto-download chapters found by library update, with included/excluded categories. | ★★ (iOS background limits apply) |
| Download ahead | While reading, download the next chapters automatically. | ★★ |
| Only on Wi-Fi | Restrict downloads to Wi-Fi. | ★★ |
| Concurrent downloads | Parallel sources and pages per source. | ★ (pick sane defaults) |
| Save as CBZ | Store chapters as .cbz archives instead of folders. | ★ |
| Downloaded-only mode | Global toggle on More: library shows only entries with downloads. Good for planes. | ★★ |
| Reindex downloads | Rescan storage if the index drifts. | ★ |

iOS note: `URLSession` background downloads keep going while the app is suspended. Store files in Application Support, excluded from iCloud backup.

## 2. Library

| Feature | What it does | Rating |
|---|---|---|
| Library filters | Tri-state filters: Downloaded, Unread, Started, Bookmarked, Completed, Tracked, custom update frequency. | ★★★ |
| More sort options | Total chapters, Latest chapter, Chapter fetch date, Last update check, Tracker score, Random. Ascending/descending. | ★★ |
| Per-category sort | Each category keeps its own sort. | ★★ |
| Display modes | Compact grid, Comfortable grid (title under cover), Cover-only grid, List. Items per row (auto or fixed). | ★★★ |
| Badges | Unread count, Downloaded count, Local source, Language overlays on covers. | ★★ (Ahoge shows unread only) |
| Continue reading button | Small play button on each cover that opens the next unread chapter directly. | ★★★ (cheap, high value) |
| Category tab options | Show/hide tabs, show item count per tab. | ★ |
| Update category | Pull to refresh only the current category. | ★★ |
| Open random entry | Picks a random series from the library. | ★ |
| Select all / Select inverse | In multi-select. | ★★ (cheap) |
| Global search from library | Search query with no local hits → "Search globally". | ★★ |
| Bulk download/delete | From library multi-select. | ★★ (after Downloads) |

## 3. Library update (background and smart)

| Feature | What it does | Rating |
|---|---|---|
| Automatic updates | Every 12h, daily, 2/3 days, weekly. | ★★★ via `BGAppRefreshTask`. iOS decides when it runs, so treat the interval as a hint. |
| Device restrictions | Only on Wi-Fi, unmetered network, or charging. | ★★ (`BGProcessingTask` supports power and network requirements) |
| Skip rules | Skip entries with unread chapters, never started, or status "Completed". | ★★★ (saves lots of requests) |
| Included/excluded categories | Choose which categories global update covers. | ★★ |
| Refresh metadata | Update covers and details during library update. | ★★ |
| Smart update | Predicts each series' next release from its chapter history and skips checks before then. Per-entry custom interval. "View upcoming updates" calendar. | ★★ (good fit for iOS's limited background time) |
| New chapter notifications | Local notification listing new chapters. | ★★★ |
| Updates badge setting | Toggle unread count on the Updates tab. | ★ |
| Mark duplicate read chapter as read | When a new upload duplicates a chapter number you already read, mark it read. | ★★ |
| Hide missing chapter indicators | Mihon shows "N missing chapters" gaps in the list. Setting hides them. | ★★ (the indicator itself is useful) |

## 4. Manga (entry) screen

| Feature | What it does | Rating |
|---|---|---|
| Bookmarks | Bookmark/unbookmark chapters, bookmark filter, swipe-to-bookmark. | ★★★ |
| Configurable swipe actions | Choose the left and right swipe actions (bookmark, read, download, none). | ★★ |
| Filter by scanlator / exclude scanlators | Hide chapters from groups you don't want. Applies to Updates too. | ★★★ (very common with aggregators) |
| Display: chapter number vs source title | Show "Chapter 12" instead of the raw source name. | ★★ |
| Default chapter settings | Save sort/filter/display as the default, and optionally apply to the whole library. | ★★ |
| Migrate | Move a series to another source and keep read progress, categories, tracking. Search runs across all sources. | ★★★ (sources die often) |
| Possible duplicates | When adding to library, warn about similar titles already in the library. Offer migrate or add anyway. | ★★ |
| Edit cover / Set cover from page | Pick a custom cover from Photos, or long-press a reader page to set it. Save and share cover. | ★★ |
| Notes | Free-text personal note per entry. | ★ |
| Tap author to search, long-press genre for global search | Ahoge already opens a genre in its source; Mihon also searches by author and searches globally on long-press. | ★ |
| Share | Share entry URL. | ★★ (cheap) |
| Tracking button | See section 7. | — |

## 5. Reader

| Feature | What it does | Rating |
|---|---|---|
| Scale type | Fit screen, Stretch, Fit width, Fit height, Original size, Smart fit. | ★★★ |
| Zoom start position | Automatic, left, right, center. | ★★ |
| Crop borders | Trim white/black margins from scans, separately for paged and long strip. | ★★★ (big readability win on phones) |
| Split wide pages | Spread pages split into two in reading order; invert placement option. | ★★★ |
| Rotate wide pages to fit / Pan / auto-zoom wide | Alternatives to splitting for double spreads. | ★★ |
| Dual page view | Two pages side by side (iPad and landscape). | ★★ (great on iPad) |
| Long strip with gaps | Separate mode instead of a webtoon toggle. | — (Ahoge already has the gap toggle) |
| Rotation lock | Free, portrait, landscape, locked portrait/landscape, per series. | ★★ |
| Custom brightness | In-app brightness separate from system, can go below system minimum. | ★★ (Ahoge's dim is close) |
| Color filter | RGBA overlay with blend modes (multiply, screen, overlay, ...). Warm night reading. | ★★ |
| Grayscale / Invert | Image filters. | ★ |
| Shaders / tile filters (WebGPU) | New upscaling/sharpening shaders. | ★ (Metal port is large) |
| Page transition animations | Page flip, stack, cube, fade, ... | ★ |
| Double tap animation speed / disable double tap zoom / disable zoom out | Fine control over gestures. | ★ |
| Tap zone layouts | L shaped, Kindle-ish, Edge, Right and Left, Disabled, with overlay shown on open. | ★★ (Ahoge has one fixed layout) |
| Volume keys to turn pages | | ✗ (iOS gives no public API; hacks get rejected) |
| Hardware keyboard / game controller | Arrow keys, space. | ★★ (iPad + keyboard; `UIKeyCommand`) |
| Show reading mode on open | Toast with current mode. | ★ |
| Skip read / filtered / duplicate chapters | Next-chapter navigation skips them. | ★★★ (skipping duplicate scanlator uploads matters) |
| Always show chapter transition | Force the "Finished / Next" page. | ★ |
| Long-press actions | Save page to Photos, share, copy, set as cover. | ★★ (Ahoge shares; add save and set-cover) |
| Bookmark from reader | Bookmark current chapter. | ★★ (with bookmarks) |
| Vertical chapter navigator | Slider on the side in long strip. | ★ |
| Flash on page change (e-ink) | | ✗ |
| Fullscreen / cutout | | — (iOS handles via safe area; add a toggle to draw under the notch) |
| Hide menu on scroll sensitivity | Long strip. | ★ |
| Preload only on Wi-Fi | Limit how far ahead pages load on cellular. | ★★ |
| Incognito mode | Global or per extension: reading doesn't record history or progress. | ★★ |
| Open in WebView/browser from reader | | ★ (cheap) |

## 6. Browse

| Feature | What it does | Rating |
|---|---|---|
| Global search | Search all installed sources at once; rows per source, "has results" filter, pinned-only. | ★★★ |
| Pin sources | Pinned section on top of Sources. | ★★ |
| Enable/disable sources and languages | Hide sources or languages you don't use. | ★★ |
| Last used source | Shows the most recent source on top. | ★ |
| Hide entries already in library | In browse results. Or dim them, as Mihon does by default. | ★★ |
| Browse display mode | Grid/list for source results. | ★ |
| Extension details | Version, language, NSFW flag, per-source settings, clear cookies per extension. | ★★ |
| Source preferences | Per-source settings exposed by the extension (quality, language, mirrors). | ★★★ (needs host API support) |
| Content warnings filter | Safe/Mixed/18+ extension filter. | ★★ |
| Update all extensions | One button. | ★★ (cheap) |
| Trust/untrusted extensions | Signature check before loading unknown extensions. | ★★ (JS extensions run with network access; worth a trust prompt for non-default repos) |
| Local source | Read CBZ/ZIP/folders from device storage. | ★★ (Files app import, `UIDocumentPicker`) |
| Deep links | Open a source URL in the app and jump to the entry. | ★★ (Share extension or `ahoge://`) |

## 7. Tracking

| Feature | What it does | Rating |
|---|---|---|
| Trackers | MyAnimeList, AniList, Kitsu, MangaUpdates, Shikimori, Bangumi: log in, link an entry, sync progress, status, score, start/finish dates. | ★★★ for AniList + MAL (OAuth via `ASWebAuthenticationSession`) |
| Update progress after reading / when marked read | Automatic one-way sync. | ★★★ |
| Enhanced trackers | Komga, Kavita, Suwayomi: two-way sync with self-hosted servers. | ★ |
| Tracked filter / tracker score sort | Library integration. | ★★ |

## 8. Data and storage

| Feature | What it does | Rating |
|---|---|---|
| Create / restore backup | Library, categories, chapters read state, history, tracking, settings, extension repos. | ★★★ (sideloaded app: a broken re-sign or 7-day expiry can wipe data. This is the most important missing feature.) |
| Automatic backups | Every 6h to weekly, keeps N files. | ★★★ (to the Files app / iCloud Drive folder) |
| Mihon/Tachiyomi backup import | Read `.tachibk` (gzip protobuf) and map Mihon sources to Ahoge extensions by name. | ★★ (brings users over) |
| Export library list | CSV of title/author/artist. | ★ |
| Storage usage | Breakdown of downloads and cache. | ★★ |
| Clear chapter cache (+ on launch) | | ★★ (Ahoge clears image cache only) |
| Clear database | Remove non-library entries, optionally keeping those with read chapters. | ★★ |
| Storage location | | ✗ (iOS sandbox; use Files app export instead) |

## 9. Security and privacy

| Feature | What it does | Rating |
|---|---|---|
| App lock | Face ID / Touch ID / passcode, lock immediately or after idle. | ★★ (`LocalAuthentication`, small) |
| Secure screen | Blur in app switcher; Mihon also blocks screenshots. | ★★ (blur is easy on iOS) |
| Hide notification content | | ★ (after notifications) |
| Crash logs / analytics | | ★ (crash log export is useful for a sideloaded app) |

## 10. More, appearance, misc

| Feature | What it does | Rating |
|---|---|---|
| Statistics | Library count, completed, read duration, chapters read/downloaded, tracked count, mean score. | ★★ |
| App language | Per-app language (iOS has this natively in Settings once strings are localized). | ★ |
| Date format / relative timestamps | | ★ |
| Tablet UI | Navigation rail, two-pane manga screen. | ★★ (iPad) |
| Render images in descriptions | | ★ |
| Onboarding | First-run setup: add repo, permissions, restore backup. | ★★ |
| App update checker | Check GitHub releases and show "What's new". | ★★ (no App Store, so users don't know updates exist) |
| Reset per-series reader settings | | ★ |
| Update library titles to match source | | ★ |
| DNS over HTTPS, custom user agent | Networking options for blocked sources. | ★ / ★★ (user agent helps with Cloudflare) |
| Help / guides links | | ★ |
| Battery optimization, Shizuku installer, MIUI warnings, Android notification channels | | ✗ |

---

## Suggested order

1. **Backup and restore (+ automatic backups).** Sideloading makes data loss likely; nothing else protects users from it.
2. **Downloads** (download, queue, indicator, delete, download-ahead). Unlocks the Downloaded filter, offline mode, and bulk actions.
3. **Reader quality:** crop borders, scale types, split wide pages, skip duplicate/read chapters.
4. **Library power:** filters, display modes, continue-reading button, more sorts.
5. **Bookmarks + scanlator filter** (small schema change, high daily value).
6. **Global search + migrate.**
7. **Background updates + notifications + skip rules.**
8. **Tracking** (AniList, MAL).
9. **App lock, statistics, update checker, iPad dual page.**

Quick wins under a day each: Select all/inverse, Share entry, Update all extensions, Continue reading button, Pin sources, Hide in-library entries in Browse, app switcher blur, save page to Photos.
