# 41: Repeating genre tags and options get unique ForEach ids

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Part of #12

## What to build
Sources that repeat a genre tag, an image URL in a description, or a filter or preference option value no longer give SwiftUI duplicate ids (missing or repeated rows, console warnings).

- Genres (`Ahoge/Features/Manga/MangaDetailView.swift:292`): show each genre once, keeping order (de-duplicate before the `ForEach`).
- Description images (`Ahoge/Features/Manga/MangaDescription.swift:82`): de-duplicate URLs, keeping order.
- Filter options (`Ahoge/Features/Browse/FilterSheet.swift:61,149`) and preference options (`Ahoge/Features/Browse/SourcePreferencesView.swift:73`): these are pickers whose tags are the values, so duplicates must not be dropped silently if labels differ; iterate by index (`Array(options.enumerated())`, id `\.offset`) and keep each `tag` as the value.
- One small helper (for example an `Array` extension "unique keeping order" in `Ahoge/Features/Shared/StringExtensions.swift` or a new shared file) is used for the two de-duplications.

## Design direction
None.

## Seams
- Unit test for the helper: `["a", "b", "a"]` → `["a", "b"]`. The view changes are checked by the CI build.

## Reuse first
- `Ahoge/Features/Shared/StringExtensions.swift` for the helper's home.

## Acceptance criteria
- [ ] None of the five listed `ForEach` calls uses `id: \.self` or `id: \.value` over a list that can repeat (quote the new lines in the report).
- [ ] Tests pass in CI.
- [ ] Committed with `Part of #12` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Other `ForEach` uses over unique data.
