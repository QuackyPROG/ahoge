# Distribution Architecture

Ahoge uses SideStore as its primary non-App-Store distribution path. The application remains a native local iOS app; GitHub provides static release hosting and metadata, not an application backend.

## Release topology

There are two independent update planes:

1. **Native Ahoge releases** — Swift/SwiftUI code, persistence contracts, importer/schema contracts, and compiled source runtime engines. These are versioned IPA releases from `QuackyPROG/ahoge`.
2. **Manga source definitions** — declarative source metadata maintained by `QuackyPROG/ahoge-extension`. A definition update does not require an Ahoge binary release when the referenced native runtime already exists in the app.

Do not merge those repositories or bundle the maintained source repository into the IPA just to simplify distribution.

## SideStore flow

Ahoge's AltSource-compatible feed is:

```text
https://raw.githubusercontent.com/QuackyPROG/ahoge/main/Distribution/source.json
```

SideStore deep link:

```text
sidestore://source?url=https://raw.githubusercontent.com/QuackyPROG/ahoge/main/Distribution/source.json
```

The user installs/configures SideStore once, adds the Ahoge source once, then installs Ahoge from the source. Later native releases appear as SideStore updates because the feed is updated automatically after each tagged GitHub Release.

SideStore signs the IPA for the user's device. Ahoge itself does not and cannot replace its own executable on stock iOS.

### Free Apple Account limits

SideStore periodically refreshes development-signed apps so their normal 7-day development signing period does not expire. With a free Apple Account, SideStore currently documents a three-active-app limit including SideStore itself and an App ID registration limit. These are Apple development-signing constraints, not Ahoge update rules.

A computer is required for SideStore's initial setup, but normal refresh/install/update operation is designed to happen on-device afterward. Device pairing state can occasionally need to be repaired after OS updates or resets.

## AltStore Classic

AltStore Classic can consume the same `Distribution/source.json` feed. Its normal signing/refresh workflow depends on AltServer running on a Mac or PC. Ahoge does not maintain a separate feed for AltStore.

## Direct IPA

Each semantic-version GitHub Release contains:

- `Ahoge.ipa`
- `Ahoge.ipa.sha256`
- `release-metadata.json`
- `release.json`

Versioned asset URLs are immutable by policy. `Distribution/source.json` points directly to those GitHub Release assets; it never points at temporary GitHub Actions artifacts.

## In-app release awareness

`More -> App Updates` reads:

```text
https://raw.githubusercontent.com/QuackyPROG/ahoge/main/Distribution/latest.json
```

The check is user-initiated when that screen opens. It does not delay application startup. Network failure leaves the rest of Ahoge fully usable.

The update UI understands three distribution channels:

- `development`
- `sideload`
- `appStore`

Sideload releases are built with `AhogeDistributionChannel=sideload` and can open the Ahoge SideStore source. App Store/TestFlight builds must use `AhogeDistributionChannel=appStore`; those builds never direct the user to an unsigned IPA.

## Signing vs updating

The GitHub Release IPA is intentionally unsigned so SideStore/AltStore-style clients can re-sign it for the installing user. Publishing a newer IPA and detecting it in an AltSource feed is **updating**. Producing a provisioning profile/signature accepted by iOS is **signing**. They are separate concerns.

App Store, TestFlight, Apple alternative marketplaces, MDM, and similar Apple-managed channels use their own signing/distribution mechanisms. Ahoge must never embed private signing keys, certificates, App Store Connect API keys, provisioning profiles, passwords, or leased enterprise credentials in the repository.

## User data across updates

The production bundle identifier remains:

```text
com.quackyprog.ahoge
```

Ahoge persists its database under the application's Application Support container (`MihonDatabase`) and stores downloads/imports below that directory. The same app identity/container is therefore expected to preserve the library, progress, downloaded data, installed source repositories, and preferences when a newer build is installed over the existing app.

The persistence layer has explicit defaulting for missing `PersistedState` fields and a schema version, and `DatabaseSnapshot` has compatibility decoding for older downloaded chapter storage. This is useful migration scaffolding, but it is not a general migration framework for arbitrary future schema changes. New incompatible persistence changes still need explicit migration tests before release.

## Future Apple-signed lane

The release pipeline separates distribution behavior from core app functionality. A future signed build can reuse the same target while overriding the distribution channel and adding an Apple signing/export stage.

Recommended future lanes:

- **development** — Xcode/local simulator/device builds.
- **sideload** — unsigned GitHub Release IPA; SideStore is primary.
- **appStore** — Apple-signed archive/export for TestFlight, public App Store, or unlisted App Store.

Do not create separate editions of core reader functionality unless Apple distribution requirements actually force a difference.

## Other distribution options

These remain investigation/fallback paths rather than Ahoge's primary architecture.

| Option | Initial setup | Updates | Signing / limits | Computer dependency | Public Ahoge fit |
| --- | --- | --- | --- | --- | --- |
| SideStore | Computer once, Apple Account, SideStore setup | Source detects updates; SideStore refreshes signatures | Free development signing normally expires after 7 days; free-account app/App-ID limits apply | Initial setup only in normal operation | **Primary sideload path** |
| AltStore Classic | Install AltStore + AltServer | Source detects updates; AltServer signs/refreshes | Apple development signing limits apply | Mac/PC normally required for refresh | Good fallback |
| Sideloadly | Install/sign IPA from desktop | Can support refresh workflows, but remains desktop-centric | Apple development signing limits apply | Mac/PC | Direct-IPA fallback |
| SideStep | Tool-specific setup | Depends on the current SideStep workflow | Not a distribution standard Ahoge should depend on | Varies | Investigate only |
| TestFlight | Apple Developer Program + App Store Connect | Apple-managed | Apple-signed beta builds; TestFlight build availability is time-limited | No end-user computer | Strong beta option |
| Public App Store | App Review | Apple-managed automatic updates | Apple Developer Program and App Review | No | Strong long-term option if review requirements can be met |
| Unlisted App Store | App Review plus unlisted-distribution approval | Apple-managed | Direct-link App Store listing; available across supported App Store regions | No | Strong option for low-discoverability public distribution |
| Apple alternative marketplace | Marketplace registration/notarization flow | Marketplace-managed | Apple notarization and regional/business terms apply | No end-user Mac/PC | Region-limited; not a universal replacement for SideStore |
| Web Distribution | Developer website + Apple eligibility/notarization | Apple distribution mechanisms | Region/eligibility requirements apply; Apple currently documents substantial eligibility requirements in the EU | No | Not currently suitable as the primary small-project path |
| Ad Hoc OTA | Register devices and provision builds | Manual/new signed builds | Paid developer account and registered-device limits | Maintainer-side Apple tooling | Poor public distribution fit |
| Apple Business Manager / Custom Apps | Organization/customer enrollment | Apple-managed | Private distribution to selected organizations | No end-user computer | Appropriate only for organizational deployments |
| MDM | Device enrollment | MDM-managed | Managed-device environment | Admin infrastructure | Enterprise/school deployments only |
| Apple Enterprise | Enterprise program + internal distribution | Organization-managed | Employees/internal use only; not a public distribution mechanism | Admin infrastructure | **Not appropriate for public Ahoge** |
| TrollStore | Version-specific exploit-compatible device | Tool-specific | Limited to supported vulnerable OS/device combinations | Varies | **Do not build around it** |
| Third-party certificate signing services | Service-specific | Service-specific | Often depends on shared/leased certificates that may be revoked | Usually none for user | **Do not make this a dependency** |
| Jailbroken package manager | Jailbroken device | Repository/package-manager updates | Requires jailbreak | Usually none | Niche only |

Apple-native alternative distribution is geographically restricted and changes with platform policy. As of October 2026 Apple documents alternative app distribution in the European Union, Brazil, and Japan, with feature sets and eligibility differing by region. This matrix should be re-audited before adopting any Apple alternative-distribution lane.
