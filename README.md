# Ahoge

Ahoge is a native Swift/SwiftUI manga reader for iPhone and iPad. The app owns the reader, library, persistence, networking, source repository importer, and native source runtime engines. Remotely maintained website definitions live separately in [`QuackyPROG/ahoge-extension`](https://github.com/QuackyPROG/ahoge-extension).

## Install with SideStore

SideStore is the primary distribution path. After SideStore is configured on the device, add this source under **Sources → Add Source**:

```text
https://raw.githubusercontent.com/QuackyPROG/ahoge/main/Distribution/source.json
```

Deep link:

```text
sidestore://source?url=https://raw.githubusercontent.com/QuackyPROG/ahoge/main/Distribution/source.json
```

Then open **Browse → Ahoge → Install**. Future Ahoge releases appear through the same source.

### Direct IPA fallback

Every versioned GitHub Release contains the unsigned device IPA and its SHA-256 checksum. SideStore performs final signing on-device.

Latest release:

```text
https://github.com/QuackyPROG/ahoge/releases/latest
```

Stable latest-IPA URL:

```text
https://github.com/QuackyPROG/ahoge/releases/latest/download/Ahoge.ipa
```

The IPA can also be downloaded on the iPhone and installed from **SideStore → My Apps → +**.

## Manga source repository

Remote website definitions are not bundled into Ahoge. The maintained catalog lives in `QuackyPROG/ahoge-extension` and can evolve independently when an existing native runtime engine is sufficient.

Repository index:

```text
https://raw.githubusercontent.com/QuackyPROG/ahoge-extension/main/index.json
```

A new Ahoge IPA is required when native app behavior, the source import/schema contract, or a compiled runtime engine changes.

## Development

Requirements are defined by `Ahoge.xcodeproj` (currently Xcode 26.3-compatible with an iOS 26.2 deployment target). Open `Ahoge.xcodeproj`, select the `Ahoge` scheme, and build normally in Xcode.

Command-line simulator build:

```bash
xcodebuild -resolvePackageDependencies -project Ahoge.xcodeproj -scheme Ahoge
xcodebuild -project Ahoge.xcodeproj -scheme Ahoge -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The production bundle identifier is `com.quackyprog.ahoge`.

## Releases

Native releases use `vMAJOR.MINOR.PATCH` tags. `.github/workflows/release.yml` verifies that the tag matches Xcode's `MARKETING_VERSION`, builds an unsigned physical-device app, validates the bundle/version/build/platform, packages `Payload/Ahoge.app` as `Ahoge.ipa`, calculates its SHA-256 and byte size, publishes the GitHub Release, and updates SideStore metadata.

Normal pushes run simulator CI and distribution validation but do not publish a release. See [`Docs/RELEASING.md`](Docs/RELEASING.md) and [`Docs/DISTRIBUTION.md`](Docs/DISTRIBUTION.md).

## Architecture

```text
Ahoge/
├── App/       App shell and application state orchestration
├── Core/      Shared platform utilities
├── Data/      Persistence, networking, imports, caches, and source runtimes
├── Domain/    Models and business rules
└── Features/  Browse, library, reader, updates, history, and settings UI
```

`Local Files` remains built in because it is application functionality rather than a remote website definition.

## License and third-party notices

Ahoge is distributed under the Apache License 2.0. See [`LICENSE`](LICENSE). Required attribution for portions adapted from third-party code is kept in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
