# Ahoge

Ahoge is a native iOS manga reader built with Swift and SwiftUI. It supports repository-driven manga sources without bundling remote web sources into the application.

## What is included

- Native iOS library and manga reader
- Chapter reading and progress tracking
- Downloads and import infrastructure
- Local Files support
- Source repository installation, refresh, and persistence
- Reusable source runtime engines used by installed source definitions
- GitHub Actions builds for simulator validation and unsigned iPhone IPA artifacts

## Source repositories

A fresh Ahoge installation does not include remote web manga sources. Remote source definitions are installed separately through the Source Repositories UI.

Maintained source definitions live in the independent [`QuackyPROG/ahoge-extension`](https://github.com/QuackyPROG/ahoge-extension) repository.

Install the maintained repository with:

```text
https://raw.githubusercontent.com/QuackyPROG/ahoge-extension/main/index.json
```

Adding or updating a source that uses an engine already supported by Ahoge does not require rebuilding the application. A new Ahoge release is needed when application behavior, the importer/schema contract, or a native runtime engine changes.

## Development

Open `Ahoge.xcodeproj` in Xcode and build the `Ahoge` scheme. The deployment target and toolchain requirements are defined by the Xcode project.

GitHub Actions validates simulator builds on pushes and pull requests. The main branch also produces an unsigned device build packaged as `Ahoge-iOS-unsigned.ipa` for sideloading workflows that provide their own signing/install mechanism.

## Architecture

Ahoge owns application code, persistence, networking, source runtime interfaces, reusable native source engines, and the source repository importer. It intentionally does not own remotely maintained source manifests or a bundled extension index.

`Local Files` remains built-in because it is application functionality, not a remote website extension.

## License and attribution

Ahoge contains code derived from the open-source `mihon-ios` project and is independently maintained. The derived code is distributed under the Apache License 2.0; see [LICENSE](LICENSE).

The rename to Ahoge does not remove upstream copyright or attribution requirements.