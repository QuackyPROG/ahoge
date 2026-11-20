# 36: Per-series reader settings go into backups and migrations

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 35
**Issue:** Part of #10

## What to build
A title's own reading mode, orientation and chapter display survive a backup and restore, and move with it on migration. Today they live only in `UserDefaults` under per-title keys (`Ahoge/Features/Reader/ReaderSettings.swift:30-42`, `Ahoge/Features/Reader/ReaderOptions.swift:116-127`, `Ahoge/Features/Manga/ChapterDisplay.swift:92-105`) and are in neither.

- One helper next to `PerSeriesReaderSettings` (`ReaderSettings.swift:248-256`) for a manga key: read the three values (nil when the title has none), write them, copy them from one key to another, remove them. It takes a `UserDefaults` so tests use an isolated suite (`ReadingMode` and `ReaderOrientation` read `.standard` today; add a defaults parameter the same way `ChapterDisplay.load(for:from:)` has one).
- `BackupManga` (`Ahoge/Backup/BackupCodec.swift:50-72`) gains three optional fields: `readerMode`, `readerOrientation` (raw strings) and `chapterDisplay` (the `ChapterDisplay` value). `BackupService.snapshot` fills them; `restoreManga` writes each one only when the title has none on the device. The format version stays 1: old backups decode (fields absent), and `backup-v1.json` in the tests still decodes.
- `migrate` (`Ahoge/Library/LibraryRepository+Migrate.swift:21-57`) copies the old key's values to the new key on every migration and copy, whatever the toggles, replacing the new key's values. The old key's values stay. This is Mihon's behaviour: `MigrateMangaUseCase.kt` sets `chapterFlags = current.chapterFlags` and `viewerFlags = current.viewerFlags` on the target with no flag check (verified in mihonapp/mihon, 2026-11-20).

## Design direction
None.

## Seams
- `BackupServiceTests` with an isolated suite: a title with mode `rightToLeft`, orientation `portrait` and a non-default chapter display round-trips through snapshot → encode → decode → restore into a fresh in-memory repo and fresh suite.
- `BackupCodecTests`: `backup-v1.json` still decodes.
- `MigrateTests`: settings copied to the new key, replacing what it had; the old key keeps its values.

## Reuse first
- `PerSeriesReaderSettings`, `ReadingMode.load/save`, `ReaderOrientation.load/save`, `ChapterDisplay.load(for:from:)/save(for:to:)`.

## Acceptance criteria
- [ ] Round-trip and migration tests pass in CI; `backup-v1.json` still decodes.
- [ ] Committed with `Part of #10` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Removing settings on Clear database (ticket 37).
