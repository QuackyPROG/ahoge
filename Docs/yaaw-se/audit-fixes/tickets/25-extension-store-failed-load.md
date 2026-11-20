# 25: ExtensionStore never overwrites an unreadable state file

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** 24
**Issue:** Fixes #7

## What to build
If `state.json` cannot be read or decoded, the user's repositories and installed sources are not wiped by the next save. Today any failure leaves `repos`/`installed` empty and the next `save()` overwrites the file with empty lists (`Ahoge/Extensions/ExtensionStore.swift:149-163`).

- `load()` tells three cases apart:
  - No file: a fresh start; saving is allowed.
  - The file exists but cannot be read: the file stays where it is; saving is blocked for this session; `lastError` says the extension list could not be read and changes will not be saved until the app restarts.
  - The file was read but cannot be decoded: it is renamed aside to `state.json.unreadable-<yyyyMMdd-HHmmss>` in the same folder; saving is blocked for this session; `lastError` says the list was unreadable and where the copy is.
- `save()` returns early (with `lastError` set) while blocked.
- Installed scripts in `scripts/` are never deleted by a blocked store.

## Design direction
None.

## Seams
- `ExtensionStoreTests` with a temp directory: garbage `state.json` → `repos` empty, `lastError` set, the renamed copy exists with the original bytes, and `addRepo`/`removeRepo` do not create a new `state.json`; no file → fresh store, saving works; a valid file loads as today.

## Reuse first
- `ExtensionStore(directory:client:)` (`ExtensionStore.swift:26-30`), `lastError` (`:16`), `SourceFixture.extensions` for a valid state file.

## Acceptance criteria
- [ ] The three cases behave as listed (tests pass in CI).
- [ ] Committed with `Fixes #7` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Repairing or merging an unreadable file.
