# 24: Log and show failed database writes

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 23
**Issue:** Part of #7

## What to build
A database write that fails is logged and shown to the user, so a change never silently disappears on relaunch. Today `LibraryRepository.write` drops every error (`_ = try? db.write(updates)`, `Ahoge/Library/LibraryRepository.swift:292-294`). Concrete trigger from #7: after More > Clear database removes a row, a screen still holding that `LibraryManga` fails every progress write.

- `write` catches the error, logs it with `AppLog.logger.error` (error text, public), and sets a published `lastWriteError` (a message). It still does not throw, so call sites stay as they are.
- `RootView` shows one alert, "Could not save changes", with the message, in the style of its existing alerts (`Ahoge/App/RootView.swift:186-195`); OK clears it. Repeated failures while the alert is up do not stack alerts.
- `DownloadManager.completed` (`Ahoge/Downloads/DownloadManager.swift:423-433`) is covered by ticket 27; do not change it here.

## Design direction
None.

## Seams
- `LibraryRepositoryTests` on `inMemory()`: upsert a title, delete its row with raw SQL (`DELETE FROM manga WHERE key = ?`), then `saveProgress` on one of its chapters: `lastWriteError` is set. A successful write leaves it nil.

## Reuse first
- `LibraryRepository.write` (`LibraryRepository.swift:292-294`), `AppLog.logger` (`Ahoge/Services/AppLog.swift:7`), `RootView`'s alert pattern.

## Acceptance criteria
- [ ] No `try?` around `db.write` in `LibraryRepository.write`.
- [ ] The test passes in CI.
- [ ] Committed with `Part of #7` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Making screens drop a cleared `LibraryManga` (not in the decision).
