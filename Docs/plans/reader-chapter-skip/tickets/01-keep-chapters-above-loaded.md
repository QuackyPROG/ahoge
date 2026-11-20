# 01 — Keep the chapters above loaded so reading on never skips a chapter

- **Status:** in-progress
- **Blocked by:** none
- **Change type:** logic
- **Model:** sonnet  <!-- the cause is a SwiftUI scroll behaviour, not visible in the diff -->

## Goal
Scrolling into the next chapter while it is still loading, or just after it loaded, keeps you on the page you scrolled to. Before, the reader jumped ahead by a whole chapter, landed near the end of the next one and marked it read.

## Cause
`ReaderModel.trimSections()` (audit ticket 15, `7653fc9`) removed every section more than one chapter before the current one. From the second chapter change onwards, entering the new chapter removed a whole chapter of content above the viewport. While the strip is still moving, the ScrollView keeps its Y offset and does not re-anchor on `scrollPosition(id:)`, so the content shifts forward by that chapter's height. `positionChanged` then saves a page near the end of the new chapter (read at the last page, or via the `.end` card) and starts loading the one after.

## Files
- modify: `Ahoge/Features/Reader/ReaderModel.swift`
- modify: `Tests/AhogeTests/ReaderModelTests.swift`

## Interfaces
```swift
// replaces trimSections(); sections are never removed while reading on (open() still resets them)
private func cancelPrefetchesBehind()
```

## Steps
1. Change `testOnlyThePreviousCurrentAndNextChapterStayLoaded` into `testChaptersAboveStayLoadedWhileReadingOn`: after reading on from chapter 1 to 3, `sections` is `/c/1` to `/c/4` and `position` is still an item. It fails against the old trim.
2. Replace `trimSections()` with `cancelPrefetchesBehind()`: cancel the waiting prefetches of sections more than one chapter before the current one, once per section, and leave `sections` alone.

## Done when
- [ ] CI (`ios.yml`) passes on the branch, including `ReaderModelTests`
- [ ] no other call site of `trimSections` remains (`grep -rn trimSections Ahoge Tests` is empty)

## User checks
- Webtoon mode, read two chapters on in a row, and keep flinging down while the next chapter is still loading: you stay in the chapter you scrolled into and it is not marked read.

## Do not
- Add dependencies.
- Touch files not listed above.
- Change `loadNext` or the transition card; in `open`, only reset `prefetchesCancelled` with `sections`.
