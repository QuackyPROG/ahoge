# Ahoge migration audit

Baseline: `QuackyPROG/mihon-ios` `main`.

## Keep
- `Mihon IOS/` application source, migrated as `Ahoge/`
- Xcode project definition and workspace metadata, migrated as `Ahoge.xcodeproj`
- application assets
- library, reader, downloads/import, local files, persistence, networking, source repository importer, runtime contracts, and referenced runtime engines
- Apache-2.0 `LICENSE`
- required repository formatting/ignore configuration

## Moved to `ahoge-extension`
- source index
- Asura Scans, QiScans, Omega Scans, and Manganato manifests
- remotely maintained base/API URLs and source metadata

## Intentionally excluded
- old Git history
- `build_log*.txt`
- stale audit/publish-readiness documents
- `Tools/`
- Xcode `xcuserdata/`
- top-level `sources/` manifests
- hardcoded `QuackyBuiltInSources.swift`
- unreferenced legacy source engines only when dependency checks prove no Swift references

## Retained for compatibility / manual review
- internal `Mihon` identifiers that are not user-visible and may affect persistence/import compatibility
- legacy source-family classifier scaffolding
- runtime engines still referenced by compiled code

## Licensing
The upstream repository is Apache License 2.0. `LICENSE` is preserved. No upstream `NOTICE` file exists in the migration baseline, so no NOTICE file was invented.
