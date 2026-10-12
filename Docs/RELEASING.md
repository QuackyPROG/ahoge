# Releasing Ahoge

Production Ahoge releases are created only from semantic-version tags matching:

```text
vMAJOR.MINOR.PATCH
```

Examples: `v1.0.0`, `v1.1.0`, `v1.1.1`.

## Maintainer workflow

Start from a clean, verified `main` branch:

```bash
git checkout main
git pull
git tag v1.2.0
git push origin v1.2.0
```

CI does the rest. Do not manually upload an IPA or edit `Distribution/source.json` for a normal release.

## What the release workflow does

`.github/workflows/release.yml` runs only for matching tags and:

1. Checks out the exact tagged commit with full history.
2. Rejects a malformed tag.
3. Rejects an already-existing GitHub Release for the tag instead of overwriting it.
4. Derives `CFBundleShortVersionString` from the tag.
5. Derives a deterministic integer build number from the tagged commit count.
6. Resolves Swift packages.
7. Builds `Release` for a generic physical iOS device with signing disabled.
8. Sets `AhogeDistributionChannel=sideload` for the generated Info.plist.
9. Verifies that a `.app` and `Info.plist` were produced.
10. Verifies `CFBundleIdentifier == com.quackyprog.ahoge`.
11. Verifies the built version/build match the release inputs.
12. Reads the built minimum iOS version.
13. Packages `Payload/Ahoge.app` as `Ahoge.ipa` and tests the ZIP structure.
14. Calculates SHA-256 and byte size.
15. Generates release notes through GitHub's release-notes API.
16. Generates `release-metadata.json` and `release.json`.
17. Creates the GitHub Release and uploads the four release assets.
18. Updates `Distribution/source.json` and `Distribution/latest.json` on `main`.
19. Validates the generated distribution JSON before pushing it.

The generated feed uses permanent versioned GitHub Release asset URLs.

## Release outputs

Every release contains:

```text
Ahoge.ipa
Ahoge.ipa.sha256
release-metadata.json
release.json
```

`release-metadata.json` records the tag, commit, bundle identifier, version, build, minimum OS, release date, IPA URL, SHA-256, release notes URL, and IPA size.

`release.json` is the lightweight manifest consumed by Ahoge's in-app update screen. `Distribution/latest.json` is updated from that manifest after the GitHub Release succeeds.

## Versioning rules

The Git tag is authoritative for the release marketing version. This keeps the normal maintainer operation to `git tag` + `git push` instead of requiring a second manual edit to Xcode project metadata.

The built IPA is still inspected after compilation. If Xcode does not emit the expected version/build or if the production bundle identifier changes, the release fails.

Do not reuse or move a published release tag. Create a new patch/minor/major version instead.

## Source-definition releases are separate

A change in `QuackyPROG/ahoge-extension` does not require an Ahoge tag when the definition references a native runtime already present in the installed Ahoge binary.

Create a new native Ahoge release when any of these change:

- app behavior or UI that must ship in the executable;
- persistence/schema/import contracts;
- a native source runtime engine;
- security/network behavior implemented in Swift;
- distribution/update code itself.

## Failure recovery

If the workflow fails **before** a GitHub Release is created, fix the problem on `main`, create a new tag, and release that version. Do not rewrite a tag that other users may already have fetched.

If the GitHub Release was created but the feed-update step fails, the release assets are still valid and immutable. Repair the workflow/feed on `main`, then regenerate `Distribution/source.json` from the published release metadata before publishing another release. Do not delete and recreate a release just to hide an automation failure.

If branch protection is later enabled on `main`, make sure the release bot has an approved way to update only `Distribution/source.json` and `Distribution/latest.json`, or move generated feed state to a dedicated distribution branch. Do not bypass review controls silently.

## Apple-signed releases later

Do not add certificates or private keys to Git. A future TestFlight/App Store job should use App Store Connect and signing credentials stored only in GitHub Actions encrypted secrets (or another approved secret store), then build the same application target with:

```text
AhogeDistributionChannel=appStore
```

That channel prevents the in-app updater from redirecting App Store/TestFlight users to a sideloaded IPA.
