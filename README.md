# Ahoge

Ahoge is a native Swift/SwiftUI iOS manga reader. The app and its remotely maintained manga source definitions are intentionally distributed separately.

## Install Ahoge

### Recommended: SideStore

SideStore is the primary non-App-Store distribution path.

1. Install and configure SideStore once.
2. Add the Ahoge source:

   ```text
   https://raw.githubusercontent.com/QuackyPROG/ahoge/main/Distribution/source.json
   ```

3. Install Ahoge from that source.
4. Future Ahoge versions appear as updates in SideStore.

SideStore source deep link:

```text
sidestore://source?url=https://raw.githubusercontent.com/QuackyPROG/ahoge/main/Distribution/source.json
```

SideStore handles periodic re-signing/refreshing; it does not remove Apple's free-development signing limits. With a free Apple Account, sideloaded development-signed apps normally need refreshing before their 7-day signing period expires.

### Alternative: AltStore Classic

Use the same source URL in AltStore Classic:

```text
https://raw.githubusercontent.com/QuackyPROG/ahoge/main/Distribution/source.json
```

AltStore deep link:

```text
altstore://source?url=https://raw.githubusercontent.com/QuackyPROG/ahoge/main/Distribution/source.json
```

AltStore Classic generally relies on AltServer on a Mac or PC for signing and refreshes.

### Direct IPA

Every versioned GitHub Release contains `Ahoge.ipa`, its SHA-256 checksum, and machine-readable release metadata.

Latest release page: <https://github.com/QuackyPROG/ahoge/releases/latest>

Stable latest-IPA URL after the first release:

```text
https://github.com/QuackyPROG/ahoge/releases/latest/download/Ahoge.ipa
```

Direct IPA installation is a fallback for Sideloadly, SideStore manual install, AltStore manual install, and other compatible signing tools. It is not the recommended update mechanism.

## Manga source repositories

A fresh Ahoge installation does not bundle remote web manga sources. The maintained source definitions live in the independent [`QuackyPROG/ahoge-extension`](https://github.com/QuackyPROG/ahoge-extension) repository.

Install the maintained manga-source repository inside Ahoge with:

```text
https://raw.githubusercontent.com/QuackyPROG/ahoge-extension/main/index.json
```

A source-definition update that uses an engine already shipped in Ahoge does not require a new Ahoge IPA. A native Ahoge release is needed when application behavior, the source schema/import contract, or a native runtime engine changes.

## Releases

Production releases are tag-driven. A tag matching `vMAJOR.MINOR.PATCH` builds an unsigned device IPA, verifies the bundle/version metadata, generates SHA-256 and release manifests, creates an immutable GitHub Release, and updates the SideStore/AltStore source automatically.

Normal pushes and pull requests run CI but do not publish production releases. See [`Docs/RELEASING.md`](Docs/RELEASING.md) and [`Docs/DISTRIBUTION.md`](Docs/DISTRIBUTION.md).

## Developer build

Open `Ahoge.xcodeproj` in Xcode and build the `Ahoge` scheme. The deployment target and toolchain requirements are defined by the Xcode project.

The production bundle identifier is `com.quackyprog.ahoge`. Do not change it casually: iOS uses the application identity to associate an update with the existing app container and its persisted data.

## Architecture

Ahoge owns application code, persistence, networking, source runtime interfaces, reusable native source engines, and the source repository importer. `ahoge-extension` owns remotely maintained source definitions. The repositories remain independently maintainable.

`Local Files` remains built in because it is application functionality rather than a remote website extension.

## License and attribution

Ahoge contains code derived from the open-source `mihon-ios` project and is independently maintained. The derived code is distributed under the Apache License 2.0; see [LICENSE](LICENSE).

The rename to Ahoge does not remove upstream copyright or attribution requirements.
