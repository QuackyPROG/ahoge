# 52: Mihon import picks the source language from the source id

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Part of #14

## What to build
A Mihon backup with a French MangaDex title restores it under the French Ahoge source, not the English one. Today `MihonBackupImporter.find` matches by name only and prefers English (`Ahoge/Backup/MihonBackupImporter.swift:100-104`), because Mihon's backup source entry has no language.

- Mihon's source id is derived from name and language. Verified in mihonapp/mihon `source-api/src/main/kotlin/eu/kanade/tachiyomi/source/online/HttpSource.kt` (2026-11-20): `generateId(name, lang, versionId)` takes `"${name.lowercase()}/$lang/$versionId"`, computes MD5, reads the first 8 bytes big-endian as a `Long`, and clears the sign bit (`and Long.MAX_VALUE`). `versionId` defaults to 1.
- `find` gets the backup's source id. Among Ahoge sources with the same name, it returns the one whose `generateId(name, lang, 1)` equals the id. With no match it falls back to today's rule (English first, then the first). MD5 comes from CryptoKit's `Insecure.MD5` (CryptoKit is already imported in `Ahoge/Extensions/RepoClient.swift:1`).
- **Inferred:** Ahoge's `RepoSource.lang` codes are the same strings as Mihon's (`en`, `fr`, `pt-BR`…). The test uses the codes Ahoge's repository index uses; if they differ in case for some languages, compare as Mihon writes them and note it.

## Design direction
None.

## Seams
- `MihonBackupImporterTests`: `generateId("MangaDex", "en", 1)` equals the value computed by the Kotlin formula (compute the expected constant once on the dev machine with Python, which is installed, from the same formula, paste it, and quote the command in a test comment); `find` with sources "MangaDex" `en` and `fr` and the `fr` id returns the `fr` source; an unknown id falls back to `en` (the existing `testSourceNameMatchIgnoresCaseAndPrefersEnglish` keeps passing).
- A full decode through `ProtoWriter` with a French source entry maps the title to the French source id.

## Reuse first
- `MihonBackupImporter.find` and `map` (`MihonBackupImporter.swift:30-48,100-104`), `ProtoWriter` (`Tests/AhogeTests/Support/ProtoWriter.swift`), `ParsedSource` id and name.

## Acceptance criteria
- [ ] Tests pass in CI.
- [ ] Committed with `Part of #14` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Sources that override their id or use another `versionId` (they fall back to the name rule).
