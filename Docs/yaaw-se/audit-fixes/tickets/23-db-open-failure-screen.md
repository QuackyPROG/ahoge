# 23: Show an error screen instead of crashing when the database cannot open

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Part of #7

## What to build
When the library database cannot open (disk full, SQLite I/O error, failed migration), Ahoge shows a full-screen error with **Retry** and **Share logs** instead of crashing. On a background launch (BGTask, background URLSession wake) it does no work and does not crash. Today `AhogeApp.init` calls `fatalError` (`Ahoge/App/AhogeApp.swift:19-23`).

- Building the services that need the database (`LibraryRepository`, `DownloadManager`, `LibraryUpdater`, `BackgroundRefresh.context`, the chapter-cache clear at `:25-27`) moves into one loader that returns the services or the error. The loader is an `ObservableObject` held by the app; `ExtensionStore`, `SourceManager` and `AppNavigator` do not need the database and stay as they are.
- When loading failed, the window shows an error screen built from `ErrorStateView` (`Ahoge/Features/Shared/ErrorStateView.swift`) with the error text, **Retry** (runs the loader again; on success the normal `RootView` appears with all environment objects) and **Share logs** (a `ShareLink` to `AppLog.exportFile()`, as `AdvancedView.swift:47-55` does). The failure is logged with `AppLog.logger.error`.
- Background launches: `BackgroundRefresh.context` stays nil, so `runUpdate`/`runBackup` already complete with `success: false` (`Ahoge/Library/BackgroundRefresh.swift:69-72,84-87`). Nothing else may touch the missing services.

## Design direction
None. The screen uses `ErrorStateView` and the app's palette as they are.

## Seams
- Unit test on the loader: pointed at a path that cannot be a database (an existing directory, via `LibraryRepository.open(at:)`), it reports failure with the error; pointed at a temp file, it reports success; Retry after fixing the path succeeds.

## Reuse first
- `LibraryRepository.open(at:)` (`Ahoge/Library/LibraryRepository.swift:45-47`), `ErrorStateView`, `AppLog.exportFile()` (`Ahoge/Services/AppLog.swift:21-27`), the `ShareLink` in `AdvancedView`.

## Acceptance criteria
- [ ] `grep -n "fatalError" Ahoge/App/AhogeApp.swift` finds nothing.
- [ ] Loader tests pass in CI.
- [ ] Committed with `Part of #7` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Write failures (ticket 24), `ExtensionStore` (ticket 25), loading the library off the main thread (#14 item 5, out of scope).
