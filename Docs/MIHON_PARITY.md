# Mihon reconstruction implementation report

Basis: TASK-001 revision 5, SPEC-003 revision 1, product 5 and engineering 6. This is a derivative implementation report, not a product contract or independent review. All six phases have production changes. Local implementation/source verification and native execution remain separate; scope remains OPEN.

Reference sources inspected read-only: Mihon v0.21.2 `9612d955db3165e1578fdf9ff19ca9b7762c4a46`, main `446f6df82c390ab760802c2fce3b677bce3f31c1`, ahoge-extension `f98bc84c1b4de89e1f310937434bc5fafd93d4e5`. Stable home/library/update/history/manga callbacks, reader preferences/navigation/viewers, global source result states, backup validation and migration flags informed behavior. Main's dual-page display concept is implemented as an opt-in native subset below; the remaining graphics frontier stays pending. No reference repository was edited.

## P01-P26 dispositions

IMPLEMENTED below means concrete production source/action/persistence paths have been added or retained and source-audited. It does not assert Swift compilation, device execution, live endpoint health or complete Mihon equivalence.

| Row | Local disposition and real paths | Gate or remaining obligation |
| --- | --- | --- |
| P01 | IMPLEMENTED: five native `Tab` roots with independent paths, one stable `.sidebarAdaptable` container, genuine Updates/package badges and delegated reselection. Library pops/scrolls, Updates opens queue, History resumes resolvable history, Browse opens search, More opens Settings. | Native UIKit delegate attachment/forwarding and same-tab iPad sidebar events need execution. |
| P02 | IMPLEMENTED: dense semantic native surfaces and compatible shared cover/row components; existing MangaCoverView privacy/cache behavior retained. | Real Dynamic Type, VoiceOver and appearance captures deferred. |
| P03 | IMPLEMENTED: adaptive grid/list, category navigation, search, persisted display/direction/tri-state downloaded/unread/bookmark/completed/local-tracking filters, real added/last-read/last-update/chapter-count/unread/latest-number/daily-random sorts; select/invert, categories, read/unread, downloads/removal confirmations and migration. | Scores and fetch-date sorts omitted because metadata is absent. |
| P04 | IMPLEMENTED: legacy single category decodes into multi-membership; Uncategorized fallback; delete removes one membership; ordering/rename/create/assignment persist; every library/category mutation API guards edit lock. | Per-category periodic scheduling unavailable. |
| P05 | IMPLEMENTED: all known library chapters grouped by real source release date; title/reader actions differ; read/bookmark/download filters in native sheet, selection/batches, confirmation, bounded refresh and per-title failures. Read state and update-seen identity are independent, including legacy marker normalization. | Calendar/upcoming schedule data unavailable; source release dates are not claimed to be detected-update timestamps. |
| P06 | IMPLEMENTED: searchable chronological persisted history, resolvable resume and unavailable recovery, individual/title/confirmed-clear deletion, favorite/category/migration. Existing dedup UUID/history limit/incognito preserved. | Device relaunch and missing-source execution deferred. |
| P07 | IMPLEMENTED: Sources/Extensions/Migrate sections; explicit local Files/import path; persisted effective enable/pin overrides, language/adult visibility and real preferences. | Source settings distinguish mutable local choices from engine information. |
| P08 | IMPLEMENTED: existing runtime page argument exposed through repository with page-one compatibility; source feeds capture immutable source/mode/submitted-query/filter descriptors with generation/cursor ownership; edits invalidate search, submissions and observed filter changes reset results/cursor/end before page one; unchanged feeds append unique IDs, stop at empty/no-new response, retain results on page failure and retry the same cursor; grid/list retained. | Popular/Latest have fixed source ordering and explicitly route to Search for filters. Only compiled supported Search controls/order keys are exposed; unsupported kinds are gated. Per-engine endpoint correctness still requires live/native checks. |
| P09 | IMPLEMENTED: actual runtime/global local searches, per-source loading/results/empty/error and incremental publication; four-request maximum, group plus retry ownership, cancellation/query/source-change generation guard, per-source retry and guarded library actions. | Swift structured-concurrency behavior must execute on Mac; syntax is not concurrency proof. |
| P10 | IMPLEMENTED: fetched available definitions separate from locally installed versions, explicit publisher trust consent, install/probe support validation, enable/disable/uninstall and real version update counts; deterministic persisted admission ordering. | HTTPS is transport, not trust; unknown versions do not invent updates. APK execution excluded. |
| P11 | IMPLEMENTED/KEEP: f98 index/package consumer, IDs and existing registry dedup/request/cookie policy retained; runtime construction guards corrected for Asura/API; last-good repository identity/URL/title/fetch timestamp/packages/source definitions preserved on transport or malformed refresh errors, with actionable retry; URL-change failure also preserves prior record. | Constructible support is not live health. Producer catalog schema 2 is not treated as a new importer input. |
| P12 | IMPLEMENTED: original library source/title -> runtime target search -> target chapter fetch -> options/mapping summary -> confirmed atomic state transfer. Exact unique chapter numbers include prologue zero; missing/ambiguous identities remain unmapped. Categories, flags, notes, local trackers, history and timestamped resume transfer; duplicate target merges safely; original removal opt-in. | Unknown target page bounds start at page zero. Original files remain original; existing target offline files/progress are preserved. |
| P13 | IMPLEMENTED: native metadata/cover hierarchy, actual library/reading/refresh/tracking/web/share/notes/categories/migration/download paths, dense chapter list with current/offline/queue/error state. | Artist/scanlator/editable metadata are not invented when producer/domain support is absent. |
| P14 | IMPLEMENTED: durable stable-ID chapter read/bookmark/page state, search/sort/tri-state filters, selection/invert/context/batch read/bookmark/download/delete. Final actual reader page marks read; explicit unread does not erase latest resume or fabricate history. | Old/missing/new Codable and behavioral Swift harness execution deferred. |
| P15 | IMPLEMENTED: default/LTR/RTL/vertical pager plus preserved legacy `vertical` long strip and separate Webtoon; independent configurable gaps, source anchors and progressive slicing/prefetch. | Gesture/resize/mode/relaunch execution deferred. |
| P16 | IMPLEMENTED: fit screen/width/height/original/smart fit, zoom start, split/order/rotation, conservative off-main border bounds with uncropped source coordinates and safe fallback; current-neighbor paging surfaces avoid full-resolution fanout. | Pixel-size/rotation/crop geometry, memory and device zoom tests deferred. |
| P17 | IMPLEMENTED: stable default/edge/vertical/L/Kindle/disabled tap layouts and axis inversion, animations respecting Reduce Motion, backgrounds/fullscreen, page number/scrub/chapter neighbors/retry, actual page Share/Save to Files, scoped awake/orientation restoration. Existing dim/grayscale color filters retained. | No hardware volume interception, Photos permission shortcut, fabricated HDR/ICC, or extra tint/invert/brightness equivalence claim. Orientation follows supported iOS window geometry. |
| P18 | IMPLEMENTED: real queue progress/error/cancel/retry/remove, confirmed file deletion, persisted pending jobs, cancellation-backed pause/resume, pending-only reorder; UUID and retained active ownership prevent overlap/stale completion. WiFi preference prevents cellular/expensive transfer transport. | Resume restarts supported partial work; no byte-resume claim. Device connectivity/storage/cancellation races deferred. |
| P19 | IMPLEMENTED local scope / GATED remote: labeled local records with validated status/chapter count/score, edit/confirmed remove, completion updates. | Accounts/login/remote search/binding/sync and remote dates unavailable; no fabricated integration or credentials. |
| P20 | IMPLEMENTED: More modes then tools/utilities/settings/support; actual preference index opens live destinations and focuses controls, including reader gaps; native grouped forms and confirmation paths. | Native focus/back/sidebar behavior deferred. |
| P21 | IMPLEMENTED: real library/history/local tracker/chapter/read/bookmark/offline metrics, cache sizes and asynchronously measured import/download file usage; no invented reading time or remote score. | Storage enumeration/performance on real data deferred. |
| P22 | IMPLEMENTED: real selected-section versioned portable Codable backup, summary, document export/import, 32MB/future/malformed/duplicate-key/identity/ownership/reference validation; replace selected sections only, preserve others, atomic write before live replacement; reference-aware shared metadata merge preserves unselected history/tracking/notes and overlapping collection chapters; complete proposed-reference validation precedes commit, caches seed from the committed state; rollback-on-write failure. Real storage/import/cache actions retained. | No downloaded/import binaries, absolute file paths, cookies/auth/security secrets or diagnostics exported. Foreign local files require reimport. Archive extraction remains existing pending capability, not claimed functional. Automatic backups are unavailable. |
| P23 | KEEP/IMPLEMENTED presentation: boot/biometric/privacy/scene/native-update backend unchanged; source/import/backup/storage onboarding and existing diagnostics/about/licenses/support/release flows retained. Corrupt/future stored snapshots fail safely without overwriting originals. | Actual unlock/app-switcher/background/privacy execution deferred. |
| P24 | IMPLEMENTED source integration: one native adaptive root container, lazy dense collections, state-specific recovery/confirmations, semantic labels, privacy-aware covers, disabled guards and bounded async lifetimes. | Full accessibility/adaptive/performance matrix remains DEFERRED_NATIVE_VALIDATION. |
| P25 | IMPLEMENTED SOURCE SUBSET: opt-in native dual-page never/always/wide and first-page-alone, adjacent full portrait grouping, RTL order, independent UIKit surfaces, focused source navigation/export/resume and final-member completion. Explicit pan/pinch/deceleration/animated-zoom ownership and latest idle-only regrouping use identity-bound production policies. | Native validation DEFERRED. HDR/gain maps, explicit ICC/EXIF equivalence, high-quality transitions, progressive decoding and WebGPU equivalence remain PENDING; scope OPEN. |
| P26 | NOT APPLICABLE ON iOS: Android APKs/resources/SAF/back semantics/Material rails/volume interception. | Native definition packages, Files, swipe-back, tabs/sidebar and UIKit alternatives used. |

## Retained and changed actions

Shell retains appearance/tint, independent navigation and cover privacy. Activity is an obsolete compatibility destination exposing the real first-class Updates/History roots. Library's decorative continuation dashboard was replaced by covers and real collection controls; Start/Continue remains available from title/context actions. Categories retain create/rename/delete and gain membership/reorder/confirmation. Manga retains cover preferences, notes, website, sharing, source refresh/retry, tracking and download management; dense chapters gain durable state and batch controls. History retains deletion and resumes only actual chapter targets; missing metadata leads to recovery rather than a fabricated ReaderView chapter. Updates no longer oscillates a per-title marker while iterating multiple rows.

Discovery retains compiled engines and exposes editable filters only in Search. SourceFeedPolicy maps compiled parser capabilities to the sheet and actual operation dispatch: Natsu supports all existing kinds; Asura/Hean sort and direction; Themesia sort; MangaDex sort and include/exclude tags; WeebCentral all existing kinds. Engine-specific sort keys replace generic invalid values. Madara/MangaBox and EZManhwa text search have no editable filter sheet; EZManhwa empty-query-only single-value filters remain gated rather than suggesting general multi-select support. Popular/Latest carry no filter state and use their existing fixed operations, with an explicit Search route. Public repository APIs expose `page`, preserving existing page-one calls through protocol extensions; internal/runtime witnesses and all call sites were inspected. Effective enable state gates feeds/details/chapters/pages, while existing offline files remain usable. New package state stores admitted definitions independently from newly fetched metadata and preserves their admission precedence through refresh. Add/change/remove repository operations preserve last-good definitions on validation failures. No Android package download/execute was introduced.

Reader reuses the existing image pipeline, tile view, snapshot lifecycle, source-page mapping, progress/resume and adjacent prefetch. Fits/crop/split/rotation keep logical source coordinates; only current neighbors instantiate paged image surfaces and continuous slices remain bounded. Settings have production effects and backward decode defaults. The reader settings Form inherits the calling navigation stack; the reader sheet creates its own stack, preserving native back behavior. Page export resolves the actual current asset and is canceled on exit. Native orientation/idle-timer changes are scoped to the reader and restore prior state. Color filter scope is explicitly dimming/grayscale, without claiming every Android shader adjustment.

Data mutations have pure Foundation seams for migration transfer, version comparison, generation identity, duplicate JSON validation and atomic snapshot writes. Normal persistence preserves portable known chapter metadata separately from downloaded snapshot pages. Migration writes one proposed snapshot before publishing state; original/target offline directories are never rebound. Backup contains selected records plus only their needed portable metadata; source-definition export rejects credential-like overrides/URLs, excludes diagnostics/security and never exports binary files. Decoding/validation finishes before model mutation; atomic failure retains the previous model/file. Download cancellation retains transport ownership until unwind, uses new UUIDs on restart/retry, and suppresses stale progress/finish commits.

## Changed files and ownership

Collection helper: RootTabView; Shared/AhogeDesignSystem and TabBarControllerAccessor; Library/CategoryManagement; Updates; History; Activity; MangaDetail; More/Settings/Stats; Tracking; AppChrome onboarding/release presentation. Reader helper: Reader files, new ReaderParityPreferences domain, border crop/export/device helpers and preference/render harnesses. Integrator: AppModel/persistence/setters/Library/Updates/ReaderProgress/MangaAccess/Tracking/SourceCaching/Storage, source service/runtime/importer/package overlays, migration/backup models and actions, queue/service changes, Browse/GlobalSearch/SourceCatalog/Backup/queue UI, checks and this report. Helpers did not edit workflow artifacts/status/evidence.

New production files: AppModel+Backup, +CollectionState, +Discovery, +Migration, +Packages, +Storage; AtomicSnapshotWriter; AhogeBackup, BackupJSONValidation, BackupRestorePlan, MigrationPlan, MigrationStateTransfer; ReaderParityPreferences; PackageInstallation, SearchGeneration, SourceFeedSession, SourceFeedPolicy; BackupViews; ReaderBorderCrop, ReaderDevicePresentation, ReaderPageExport. Existing changed files are visible in the final repository identity/diff. THIRD_PARTY_NOTICES records actual Mihon tap-policy adaptation and native modifications; no branding/assets were copied.

Protected source audit: no Xcode project/settings/dependencies/assets, CI/distribution, external checkout, authenticator, background manager, AppModel+Security, MangaCoverView internals, NativeUpdate backend or managed YAAW bytes changed. AppChrome changes are onboarding/release presentation only. New setters, Codable defaults/initializers, protocol witnesses and enum consumers were inspected. Native typechecking remains required.

## Exact application and supporting file paths

The following is the full current reconstruction application/checker/report/notices working-tree change set against HEAD, including the existing integration preserved during R5. It excludes framework/workflow artifacts and pre-existing audit images. R5 specifically changed AppModel+Backup, AppModel+Packages, AppModel+Sources, SourceRepoImporter, PackageInstallation, SourceDomain, BrowseView, MihonDomainRegression, validate_mihon_reconstruction and this report, and added BackupRestorePlan and SourceFeedSession.

- `Ahoge/App/AppChrome.swift`
- `Ahoge/App/AppModel+Backup.swift`
- `Ahoge/App/AppModel+CollectionState.swift`
- `Ahoge/App/AppModel+DiagnosticsAndCache.swift`
- `Ahoge/App/AppModel+Discovery.swift`
- `Ahoge/App/AppModel+Downloads.swift`
- `Ahoge/App/AppModel+Library.swift`
- `Ahoge/App/AppModel+MangaAccess.swift`
- `Ahoge/App/AppModel+Migration.swift`
- `Ahoge/App/AppModel+Packages.swift`
- `Ahoge/App/AppModel+Preferences.swift`
- `Ahoge/App/AppModel+ReaderProgress.swift`
- `Ahoge/App/AppModel+Repositories.swift`
- `Ahoge/App/AppModel+SourceCaching.swift`
- `Ahoge/App/AppModel+Sources.swift`
- `Ahoge/App/AppModel+Storage.swift`
- `Ahoge/App/AppModel+Tracking.swift`
- `Ahoge/App/AppModel+Updates.swift`
- `Ahoge/App/AppModel.swift`
- `Ahoge/App/DownloadQueueCoordinator.swift`
- `Ahoge/App/DownloadsService.swift`
- `Ahoge/Data/AppStateStore.swift`
- `Ahoge/Data/AtomicSnapshotWriter.swift`
- `Ahoge/Data/FileDatabaseCoordinator.swift`
- `Ahoge/Data/InternalSourceRepository.swift`
- `Ahoge/Data/RuntimeSourceRepository.swift`
- `Ahoge/Data/ServiceContracts.swift`
- `Ahoge/Data/SourceRepoImporter.swift`
- `Ahoge/Domain/Downloads/DownloadsDomain.swift`
- `Ahoge/Domain/Library/LibraryDomain.swift`
- `Ahoge/Domain/Library/LibrarySortMode.swift`
- `Ahoge/Domain/Persistence/AhogeBackup.swift`
- `Ahoge/Domain/Persistence/BackupJSONValidation.swift`
- `Ahoge/Domain/Persistence/BackupRestorePlan.swift`
- `Ahoge/Domain/Persistence/MigrationPlan.swift`
- `Ahoge/Domain/Persistence/MigrationStateTransfer.swift`
- `Ahoge/Domain/Persistence/PersistedState.swift`
- `Ahoge/Domain/Preferences/PreferencesDomain.swift`
- `Ahoge/Domain/Preferences/ReaderParityPreferences.swift`
- `Ahoge/Domain/Source/PackageInstallation.swift`
- `Ahoge/Domain/Source/SearchGeneration.swift`
- `Ahoge/Domain/Source/SourceDomain.swift`
- `Ahoge/Domain/Source/SourceFeedSession.swift`
- `Ahoge/Domain/Source/SourceFeedPolicy.swift`
- `Ahoge/Features/Activity/ActivityView.swift`
- `Ahoge/Features/Browse/BrowseView.swift`
- `Ahoge/Features/Browse/GlobalSearchView.swift`
- `Ahoge/Features/Browse/SourceCatalogViews.swift`
- `Ahoge/Features/Downloads/DownloadQueueView.swift`
- `Ahoge/Features/History/HistoryView.swift`
- `Ahoge/Features/Library/CategoryManagementView.swift`
- `Ahoge/Features/Library/LibraryView.swift`
- `Ahoge/Features/Manga/MangaDetailView.swift`
- `Ahoge/Features/Migration/MigrationViews.swift`
- `Ahoge/Features/More/BackupViews.swift`
- `Ahoge/Features/More/MoreView.swift`
- `Ahoge/Features/More/SettingsViews.swift`
- `Ahoge/Features/More/StatsView.swift`
- `Ahoge/Features/Reader/ReaderBorderCrop.swift`
- `Ahoge/Features/Reader/ReaderDevicePresentation.swift`
- `Ahoge/Features/Reader/ReaderPageExport.swift`
- `Ahoge/Features/Reader/ReaderPageSurface.swift`
- `Ahoge/Features/Reader/ReaderRenderModels.swift`
- `Ahoge/Features/Reader/ReaderSettingsView.swift`
- `Ahoge/Features/Reader/ReaderTiledPageView.swift`
- `Ahoge/Features/Reader/ReaderUIComponents.swift`
- `Ahoge/Features/Reader/ReaderView+ChromeStyle.swift`
- `Ahoge/Features/Reader/ReaderView+ComputedState.swift`
- `Ahoge/Features/Reader/ReaderView+PagerInteraction.swift`
- `Ahoge/Features/Reader/ReaderView+SnapshotLifecycle.swift`
- `Ahoge/Features/Reader/ReaderView+VerticalScroll.swift`
- `Ahoge/Features/Reader/ReaderView.swift`
- `Ahoge/Features/RootTabView.swift`
- `Ahoge/Features/Shared/AhogeDesignSystem.swift`
- `Ahoge/Features/Shared/TabBarControllerAccessor.swift`
- `Ahoge/Features/Tracking/TrackingViews.swift`
- `Ahoge/Features/Updates/UpdatesView.swift`
- `Docs/MIHON_PARITY.md`
- `Scripts/MihonDomainRegression.swift`
- `Scripts/ReaderPreferencesRegression.swift`
- `Scripts/ReaderRenderRegression.swift`
- `Scripts/run_mihon_domain_regressions.py`
- `Scripts/validate_mihon_reconstruction.py`
- `Scripts/validate_reader_syntax.py`
- `Scripts/validate_workflow.mjs`
- `THIRD_PARTY_NOTICES.md`

## Actual available checks

- `git diff --check`: PASS, with normal Windows LF/CRLF informational warnings.
- `python Scripts/validate_distribution.py Distribution/source.json Distribution/latest.json`: PASS, "Distribution metadata is valid."
- `node .yaaw-core/system/engine/integrity.mjs --workspace .`: HEALTHY, no modified/missing/unsafe managed paths.
- `node --check Scripts/validate_workflow.mjs`: PASS.
- `node Scripts/validate_workflow.mjs`: 13 checks PASS. These are synthetic workflow fixtures and certify neither application/native behavior nor independent acceptance.
- `python Scripts/validate_mihon_reconstruction.py --parser-path <temporary tree-sitter target>`: syntax/interface/source/fixture audit PASS with zero new diagnostics. The unchanged BiometricAuthenticator `.success(())` grammar limitation reproduces at HEAD. Parser/source assertions do not compile or execute Swift.
- `python Scripts/run_mihon_domain_regressions.py`: DEFERRED_NATIVE_VALIDATION because `swiftc` is unavailable. Actual Swift assertions are unexecuted, not PASS.

Supporting regression harnesses exercise legacy/missing/new fields and round-trip, read vs seen, exact/ambiguous/missing/prologue/duplicate migration mapping and edit lock/target merge, malformed/future/duplicate/reference/selected backup content, atomic write failure, conservative version comparison, generation cancellation identity and queue ownership/stale finish; reader preferences exercise defaults/clamps/tap layouts/inversion, and reader geometry exercises source anchors/split/rotated partitions. These are real Swift production seams, but only fixture/source checks ran here. UIKit AppModel orchestration and actual network races still need native integration execution.

## R5 bounded repairs

F-006: `BackupRestorePlan` is the production selected-section policy. Shared title/chapter metadata is retained by stable identity; library-only restore no longer drops history/tracker/note-only metadata. Supporting history imports preserve existing collection chapters on overlapping identities and add missing chapter references. The complete proposed snapshot's references are checked before atomic write, and caches rebuild from that snapshot with existing offline chapters retained. Existing incomplete references cause a reported validation failure before publication. Regression fixtures cover both selections, encoded cold launch, rejection preservation and the existing atomic write failure.

F-007: importer refresh uses `RepositoryRefreshPolicy`, preserving every last-good catalog field and updating only error state. Add failure uses the same preservation method. `PackageAdmission` contains the unchanged runtime admission decision, separate from fetched versions/catalog rows. Injected transport/malformed-response failures plus record/installation round-trip, runtime version retention, catalog entries, disable/uninstall and successful retry are actual Foundation harness fixtures. They have not run here; native catalog detail/navigation and live-network integration remain required.

F-008: `SourceFeedSession` issues immutable descriptor/generation/page requests consumed directly by SourceView. Search edits cancel/invalidate and clear results; the UI requests submission. Each supported Search filter change applies immediately with a synchronous reset to page one, so old-filter results cannot publish. Next page reads the submitted descriptor, and unchanged retry retains its cursor. Deterministic request-spy fixtures cover edit-before-submit, filter change in flight, late responses, append, retry and exhaustion. These Swift assertions remain unexecuted on this host.

## R6 bounded repair

F-009: Popular and Latest now show fixed-ordering copy and a Search route, with no editable filter button or filter values in their descriptors. Search field submission enters Search. Search retains its own selections when switching modes; they become effective only upon returning to Search. The filter sheet exposes only supported compiled parser kinds and exact engine order keys, with a source-default ordering choice. The generic imported filter schema is metadata, not runtime capability authority. Unsupported text-search engines explain that editable filters are unavailable. No backend filter API or semantics were added.

`SourceFeedOperation.make` is consumed by the actual AppModel dispatcher and drops filters from feed-only operations; Search passes only `SourceSearchFilters.applying` values to the existing search API. SourceView uses the same capability policy to build descriptors and render controls. Existing generation/cursor/late-response guards are unchanged. Foundation fixtures exercise fixed Popular/Latest operations despite supplied filters, supported Search values on page one/append/retry, and engine-specific gates/order keys. Source assertions check the production dispatcher and UI call sites. These are source/fixture audits here; actual Swift execution and live endpoint behavior remain deferred.

## R7 bounded repair

F-010: Natsu's existing URL recognition now lives in `NatsuSearchQuery.deepLinkSlug`, shared by the actual Natsu runtime (search and detail) and `SourceSearchFilters`. Both UI and AppModel policy receive the exact `descriptor.context.baseURL` used to construct that runtime. Recognition preserves whitespace trimming, exact Foundation host equality, `/manga/<slug>` path matching, nested paths, query/fragment and scheme/port behavior; no URL/ID recognition was broadened. Recognized direct lookup exposes no editable filters and explains that it resolves one title without additional pages. Query edits dismiss the filter sheet, invalidate results and require submission. Observing raw filter selections separately prevents a query-dependent capability change from accidentally submitting a query.

The immutable submitted descriptor captures pagination support. `SourceFeedSession` refuses subsequent requests for direct lookup and marks its first successful response terminal even when nonempty. First-page failure retries page one; stale generations cannot publish. `SourceFeedOperation` drops unsupported filters and normalizes direct requests to page one. Ordinary text keeps supported filters and existing first/append/retry cursors. Popular/Latest remain paginated and filter-free even if the search field contains a direct URL.

Whole compiled SourceRuntime search audit: Natsu alone has a direct URL short circuit; Natsu runtime IDs are ordinary search inputs. Madara and MangaBox blank queries delegate to Latest with `request.page`, retaining pagination and existing filter gating. EZManhwa uses paginated `/series` for blank queries and `/series/search` for text; its conservative filter gate stays. Themesia, Asura, MangaDex, HeanCMS and WeebCentral consume pages for blank/text/URL-shaped queries; none has a direct URL/ID search branch. Existing request parsers, transport/cache/rate rules and recognition behavior are preserved. No new source capability is claimed.

Exact R7 files: `Ahoge/Domain/Source/SourceFeedPolicy.swift`, `Ahoge/Domain/Source/SourceFeedSession.swift`, `Ahoge/Data/Sources/NatsuIdSourceEngine.swift`, `Ahoge/App/AppModel+Discovery.swift`, `Ahoge/Features/Browse/BrowseView.swift`, `Scripts/MihonDomainRegression.swift`, `Scripts/validate_mihon_reconstruction.py`, and this report. Existing F-006–009 repairs and reconstruction are retained. Added production-seam Swift fixtures cover matching/mismatching hosts and paths, nested/query/fragment/scheme/port/whitespace cases, ID/text/blank input, direct filters/terminal success/empty/failure retry/stale response, and other adapters' preserved pagination. Available syntax/interface/fixture audit passes; these Swift assertions remain unexecuted without swiftc. Local implementation/source verification is separate from DEFERRED_NATIVE_VALIDATION; independent review remains required and scope stays OPEN.

## Dual-page subset and lifecycle completion

The default remains never/first-page-alone true. Always/wide apply only to horizontal pagers; wide uses measured usable width greater than height and unknown geometry falls back to singleton. Known full portrait neighbors pair in source order; cover, unmatched final page, unknown/square/wide assets, split halves and slices remain singleton. Both existing surfaces retain independent fit/crop/zoom/loading/retry and bounded current-neighbor requests. RTL changes physical order without changing stored logical/source identity, page count, slider, chapter sentinels or focus. Accessibility describes the range and focused page; member focus actions and focused-source export remain available.

`ReaderInteractionPolicy.swift` is the Foundation production activity/registration/publication/navigation seam. UIKit observes its existing pan/pinch recognizers without replacing delegates, atomically hands pan to deceleration, and owns animated double-tap zoom through its animator terminal/cancellation with captured animation identity. Captured chapter/session, member, mounted-host and configuration/load generation identities accompany callbacks through viewport/surface state. Matching failure/retry/disappearance/dismantle/departure retires ownership; stale or offscreen events cannot release/reacquire replacements. Activities overlap independently. Resting zoom does not defer snapshots; it retains dual navigation suspension and singleton edge-turn policy. Reader pager phase, transition state and chapter transition also gate publication. New requests coalesce while preserving explicit source/end intent; later user focus supersedes it. Consumption precedes commit effects, and ordinary commit reconciles matching live members rather than clearing all state.

`ReaderProgressPolicy.swift` supplies the decisions consumed by actual ReaderView progress/export and AppModel record/chapter-state/history writes. A committed final full-source spread marks read with earlier focused resume/history/export. Pending/old-chapter/noncommitted/offscreen/split/slice visibility cannot assert that override. Model clamping, same-chapter count floor, sticky read, incognito history suppression, history UUID dedup/limit, timestamp/persistence/tracker effects and manual edit-lock guards are retained. The Foundation render harness drives these production decisions and overlapping/stale/cancel/deceleration/pending/transition sequences; it is unexecuted on Windows without swiftc. Syntax/source audit is distinct from native proof.

This increment touches ReaderTiledPageView, ReaderPageSurface, ReaderView and its ComputedState/PageStateUpdates/PagerInteraction/SnapshotLifecycle/ChapterNavigation/LoadLifecycle consumers, ReaderPageExport, ReaderUIComponents pager cancellation, AppModel+ReaderProgress, the two focused production helpers, ReaderRenderRegression, its existing runner and this report. It preserves the recovered grouping/preferences/presentation work and R8 source/restore repairs. No additional graphics capability or full P25 completion is claimed.

Additional required Mac/device cases: run the actual Foundation reader/preferences/render harnesses, then exercise both surfaces independently and simultaneously at scale 1, above/below 1, overlapping pan/pinch, pan-to-deceleration, cancelled/failed gestures, interrupted double-tap zoom and repeated terminal events. During ownership request metadata, dual/cover/fit/crop policy changes, rotation and iPad resizing; verify newest snapshot publishes once after all owners/pager/transition gates release with focus intact. Exercise independent load failure/retry, host replacement/disappearance/dismantle, chapter departure and stale callbacks. Verify default/cover on-off/odd-even/LTR-RTL/vertical exclusions; either-member target, slider, final trailing-member completion with earlier focus, exit/relaunch/incognito resume/history and focused save/share. Check VoiceOver range/focus/actions, light/dark/largest Dynamic Type and memory/prefetch/cancellation of two large surfaces. All remain DEFERRED_NATIVE_VALIDATION until real Mac/device execution.

## R9 bounded adapter repairs

F-011: Both actual `ReaderPageSurface` call sites now require the current epoch, visibility and event callback. Continuous/webtoon visibility comes from measured positive viewport intersections keyed by current render-member IDs, including slices, through the shared `ReaderSurfaceVisibility` production policy. Pager/vertical-pager visibility remains the committed display group's members. Frame callbacks carry their originating epoch. Reconciliation runs even with empty frames or during slider activity, retires departed members, preserves other live owners and retries pending publication. Surface disappearance/dismantle retains exact-identity retirement. Mode publication advances the epoch only after all idle gates open; continuous containers are keyed by that epoch, restoring the focused page on replacement and rejecting old frame/phase callbacks.

The outer continuous/webtoon ScrollView also contributes identity-bound ownership through native `onScrollPhaseChange`: tracking/interacting, deceleration and programmatic ScrollViewReader animation remain owned through idle/cancellation/disappearance. It uses the existing reducer with a distinct container member, so an outer idle cannot release a simultaneous inner pinch, and scrolling out an inner member cannot release a live outer deceleration. This covers fit-scale gestures that belong to the outer scroll instead of the image host. The project already targets iOS 26.2; the phase meanings and callback are documented by [Apple](https://developer.apple.com/documentation/swiftui/view/onscrollphasechange(_:)). There is no gesture-duration timer.

F-012: `ReaderViewportMeasurement` retains optional finite positive measured geometry separately from finite layout-safe dimensions. Grouping consumes only measured geometry; width-only/height-only zero, negative or nonfinite input cannot become a measured wide viewport. Startup and invalid resize fall back to singleton grouping, and subsequent valid landscape measurements can pair again.

Exact repair files: `ReaderInteractionPolicy.swift`, `ReaderPageSurface.swift`, `ReaderUIComponents.swift`, `ReaderView.swift`, its ComputedState/PageStateUpdates/SnapshotLifecycle/VerticalScroll/ChapterNavigation/LoadLifecycle extensions, `Scripts/ReaderRenderRegression.swift`, and this report. Added Foundation fixtures exercise those same production visibility/measurement/reducer/pending policies for every pager direction, vertical pager, continuous and webtoon; actual frame selection, overlapping inner/outer activity, metadata/mode deferral, terminal/latest-only flush, stale generation/epoch, disappearance/visibility retirement, layout safety and invalid-to-valid recovery. Existing grouping/progress/preference and stable reconstruction fixtures remain. Swift assertions are unexecuted without swiftc; available parser/source gates do not establish runtime behavior.

Additional Mac/device obligations: in continuous and webtoon at fit scale, drag then fling the outer scroll while requesting metadata/mode changes; verify no publication during tracking, drag, deceleration or programmatic scrolling. Overlap an inner pinch/animated zoom with outer activity; end/cancel either first, scroll a member offscreen, retry, replace mode/container and change chapter; verify only matching activity retires and the newest pending snapshot commits once with focused anchor preserved. Repeat in horizontal and vertical pagers. Start with zero width/height, inject invalid measurements, resize to portrait/square/landscape and recover after each; verify wide remains singleton until both dimensions are finite and positive. Keep all earlier simultaneous-gesture/progress/export/VoiceOver/memory and full-app checklists. Native execution remains DEFERRED_NATIVE_VALIDATION; scope remains OPEN.

## DEFERRED_NATIVE_VALIDATION

Run on a Mac:

```sh
xcodebuild -resolvePackageDependencies -project Ahoge.xcodeproj -scheme Ahoge
xcodebuild -project Ahoge.xcodeproj -scheme Ahoge -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
python3 Scripts/run_mihon_domain_regressions.py
```

Then execute all five tabs, separate navigation/search state, normal switching/reselection/sidebar; Library categories/filter/display/batch/lock/relaunch; chronological Updates/read-vs-seen/bookmark/count/partial refresh; History resume/deletion/incognito/unavailable recovery; actual source/global search/pagination/filter/cancellation/partial failure, trust/install/update/disable/uninstall/repo failure; migration mapping/duplicate target/known-vs-unknown pages/history/timestamps/rollback/offline file preservation; queue pause/retry/reorder/WiFi/offline/storage/cancel-finish race/relaunch; all reader modes/fits/zoom/split/crop/rotation/tap/chapter transitions/current-page export, progress after resize/exit/relaunch and native orientation/awake restoration; settings focus/persistence/local tracking; selected backup export/preview/invalid/future/duplicate/reference/atomic failure/confirmed restore/unselected preservation; corrupt/future stored-state recovery and privacy/unlock.

Use real compact/large iPhone/iPad, landscape/light/dark/largest Dynamic Type, VoiceOver selection/focus/actions/status, Reduce Motion/Transparency, Increase Contrast, safe areas/sheets/native back and hidden cover states. Measure large-image memory, current-neighbor decode, rotated wide-page partition coverage, scroll responsiveness/prefetch/cancellation and network failures. Record OS/build/seeds/steps/actual outputs and genuine capture paths only when executed. No simulator/device images or Swift/native success are fabricated. P25 and all these native obligations remain open; CI/release publication was not authorized or performed.
