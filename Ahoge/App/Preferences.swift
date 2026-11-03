import Foundation

/// Every app-wide setting in one list: its stored key and default. Views bind with
/// `@AppStorage(Pref.x.name)`; logic reads `Pref.x.value(in:)`. Backup and settings search walk this
/// list, so a new setting goes here first. Never rename a stored string: users' settings live under it.
enum Pref {
    struct Key<Value> {
        let name: String
        let defaultValue: Value

        init(_ name: String, _ defaultValue: Value) {
            self.name = name
            self.defaultValue = defaultValue
        }

        /// The stored value, or the default when unset or of another type.
        func value(in defaults: UserDefaults = .standard) -> Value {
            defaults.object(forKey: name) as? Value ?? defaultValue
        }

        func set(_ value: Value, in defaults: UserDefaults = .standard) {
            defaults.set(value, forKey: name)
        }
    }

    // MARK: Library
    /// A `LibrarySort.stored` ("title:asc"); older versions kept a plain label, which still reads.
    static let librarySort = Key("library.sort", "title:asc")
    /// A `LibraryFilters.stored` (JSON); empty is no filter.
    static let libraryFilters = Key("library.filters", "")
    /// Each category keeps its own sort (`MangaCategory.sortMode`, and `libraryDefaultShelfSort` for Default).
    static let perCategorySort = Key("library.perCategorySort", false)
    /// Default (titles in no category) has no category row, so its own sort lives here; empty follows the global sort.
    static let libraryDefaultShelfSort = Key("library.defaultShelfSort", "")
    /// A `LibraryDisplayMode`.
    static let libraryDisplayMode = Key("library.displayMode", "compact")
    /// Grid columns in portrait and landscape; 0 fits as many as the width allows.
    static let libraryColumnsPortrait = Key("library.columnsPortrait", 0)
    static let libraryColumnsLandscape = Key("library.columnsLandscape", 0)
    static let libraryBadgeUnread = Key("library.badge.unread", true)
    static let libraryBadgeDownloaded = Key("library.badge.downloaded", false)
    static let libraryBadgeLanguage = Key("library.badge.language", false)
    static let libraryBadgeLocal = Key("library.badge.local", false)
    static let libraryShowCategoryTabs = Key("library.showCategoryTabs", true)
    static let libraryShowItemCount = Key("library.showItemCount", true)
    static let libraryShelf = Key("library.shelf", 0)
    /// A category id, `LibraryPrefs.uncategorized` or `LibraryPrefs.alwaysAsk`.
    static let libraryDefaultCategory = Key("library.defaultCategory", LibraryPrefs.alwaysAsk)
    /// A play button on library covers that opens the next unread chapter.
    static let libraryContinueButton = Key("library.continueButton", false)
    static let libraryLastUpdated = Key<Date?>("library.lastUpdated", nil)

    // MARK: Browse
    /// Hides titles already in the library from browse results instead of dimming them.
    static let browseHideInLibrary = Key("browse.hideInLibrary", false)
    /// Source ids pinned to the top of Sources.
    static let pinnedSources = Key<[String]>("browse.pinnedSources", [])
    static let lastUsedSource = Key("browse.lastUsedSource", "")
    /// Source ids hidden from Sources and global search (they stay installed).
    static let disabledSources = Key<[String]>("browse.disabledSources", [])
    /// Language codes hidden from Sources and global search.
    static let disabledLanguages = Key<[String]>("browse.disabledLanguages", [])
    /// A `ContentFilter`: which sources to show by the repository's 18+ flag.
    static let browseContentFilter = Key("browse.contentFilter", "all")
    /// A `LibraryDisplayMode` for a source's results; Browse offers the compact grid and the list.
    static let browseDisplayMode = Key("browse.displayMode", "compact")
    /// Global search covers pinned sources only.
    static let globalSearchPinnedOnly = Key("browse.globalSearchPinnedOnly", false)

    // MARK: Reader
    static let readerMode = Key("reader.mode.default", "webtoon")
    static let readerBackground = Key("reader.background", "black")
    static let readerShowPageNumber = Key("reader.showPageNumber", true)
    static let readerKeepScreenOn = Key("reader.keepScreenOn", true)
    /// −75…100: below 0 a black overlay, above 0 the screen's own brightness (restored on close); 0 is off.
    static let readerBrightness = Key("reader.brightness", 0)
    /// A `TapZoneLayout`.
    static let readerTapLayout = Key("reader.tapLayout", "standard")
    static let readerInvertTaps = Key("reader.invertTaps", false)
    /// Shows the tap zones for a moment when a paged reader opens.
    static let readerShowTapZones = Key("reader.showTapZones", true)
    static let readerShowModeToast = Key("reader.showModeToast", true)
    static let readerDrawUnderCutout = Key("reader.drawUnderCutout", true)
    static let readerWebtoonPadding = Key("reader.webtoonPadding", 0.0)
    static let readerWebtoonGap = Key("reader.webtoonGap", false)
    /// Webtoon: how little scrolling hides the menu. 0 off, 1 low, 2 medium, 3 high.
    static let readerHideMenuOnScroll = Key("reader.hideMenuOnScroll", 2)
    static let readerCropBordersPaged = Key("reader.cropBordersPaged", false)
    static let readerCropBordersWebtoon = Key("reader.cropBordersWebtoon", false)
    /// A `ReaderScaleType`.
    static let readerScaleType = Key("reader.scaleType", "fitScreen")
    /// A `ReaderZoomStart`.
    static let readerZoomStart = Key("reader.zoomStart", "auto")
    /// A `WidePageMode`.
    static let readerWidePages = Key("reader.widePages", "off")
    static let readerInvertSplit = Key("reader.invertSplit", false)
    /// A `DualPageMode`.
    static let readerDualPage = Key("reader.dualPage", "off")
    /// A `ReaderOrientation`, for series without their own.
    static let readerOrientation = Key("reader.orientation.default", "free")
    static let readerDoubleTapZoom = Key("reader.doubleTapZoom", true)
    static let readerDisableZoomOut = Key("reader.disableZoomOut", false)
    /// 0 no animation, 1 normal, 2 fast.
    static let readerDoubleTapSpeed = Key("reader.doubleTapSpeed", 1)
    static let readerColorFilter = Key("reader.colorFilter", false)
    /// 0xAARRGGBB.
    static let readerColorFilterColor = Key("reader.colorFilterColor", 0x40FF_8C00)
    /// A `ColorFilterMode`.
    static let readerColorFilterMode = Key("reader.colorFilterMode", "normal")
    static let readerGrayscale = Key("reader.grayscale", false)
    static let readerInvertColors = Key("reader.invertColors", false)
    static let readerSkipRead = Key("reader.skipRead", false)
    /// Skips chapters the chapter list filters out, excluded scanlators included.
    static let readerSkipFiltered = Key("reader.skipFiltered", true)
    static let readerSkipDuplicates = Key("reader.skipDuplicates", false)
    /// Off: the card between chapters shows only when chapters are missing in between.
    static let readerAlwaysShowTransition = Key("reader.alwaysShowTransition", true)
    /// On cellular, prefetch only the next page.
    static let readerPreloadOnlyOnWiFi = Key("reader.preloadOnlyOnWiFi", false)

    // MARK: Entry screen
    /// What swiping a chapter row does: none, bookmark, read or download. Right is the swipe that starts at the left edge.
    static let swipeRight = Key("entry.swipeRight", "read")
    static let swipeLeft = Key("entry.swipeLeft", "bookmark")
    /// Hides the "N missing chapters" notice between chapter rows.
    static let hideMissingChapters = Key("entry.hideMissingChapters", false)
    /// A newly fetched chapter with the number of a chapter already read is marked read.
    static let markDuplicateRead = Key("entry.markDuplicateRead", false)
    /// The `ChapterDisplay` JSON ("Set as default"); empty is the built-in default.
    static let chapterDisplayDefault = Key("entry.chapterDisplayDefault", "")

    // MARK: Appearance
    static let theme = Key("ui.theme", "standard")
    static let themeMode = Key("ui.themeMode", "system")
    static let pureBlack = Key("ui.pureBlack", false)

    // MARK: Privacy
    /// Covers the app in the app switcher.
    static let secureScreen = Key("security.secureScreen", false)
    /// Reading saves no progress or history.
    static let incognito = Key("security.incognito", false)
    /// Source ids read in incognito whatever the global switch says.
    static let incognitoSources = Key<[String]>("security.incognitoSources", [])
    /// Asks for Face ID, Touch ID or the passcode on launch and after the app was in the background (`lockAfter`).
    static let requireUnlock = Key("security.requireUnlock", false)
    /// Minutes in the background before the lock asks again (`LockPolicy.afterOptions`): 0 always, -1 never.
    static let lockAfter = Key("security.lockAfter", 0)

    // MARK: Backup
    /// Hours between automatic backups; 0 is off.
    static let autoBackupInterval = Key("backup.autoInterval", 0)
    /// How many automatic backups to keep in Documents/Backups.
    static let autoBackupKeep = Key("backup.autoKeep", 4)
    /// When the last automatic backup was made (seconds since 1970).
    static let autoBackupLast = Key("backup.autoLast", 0.0)

    // MARK: Downloads
    /// How many sources download at once; each source downloads one chapter at a time (Mihon's rule).
    static let downloadConcurrentSources = Key("download.concurrentSources", 2)
    /// Pages fetched at once within one chapter.
    static let downloadConcurrentPages = Key("download.concurrentPages", 3)
    static let downloadOnlyOnWiFi = Key("download.onlyOnWiFi", true)
    /// Whether the queue was paused, so a relaunch keeps it paused. Device state, not backed up.
    static let downloadPaused = Key("download.paused", false)
    /// Zips each finished chapter into one .cbz file.
    static let saveAsCBZ = Key("download.saveAsCBZ", false)
    static let removeAfterMarkedRead = Key("download.removeAfterMarkedRead", false)
    /// 0 is off, 1 deletes the chapter just read, 2–5 the 2nd–5th to last read.
    static let removeAfterReading = Key("download.removeAfterReading", 0)
    static let removeBookmarkedToo = Key("download.removeBookmarked", false)
    /// Unread chapters to fetch ahead while reading a downloaded chapter; 0 is off.
    static let downloadAhead = Key("download.ahead", 0)
    /// Downloads chapters a library update finds (categories with flag bit 1 are left out).
    static let downloadNewChapters = Key("download.newChapters", false)
    /// Library, Updates and History show only what is downloaded.
    static let downloadedOnly = Key("download.downloadedOnly", false)
    /// Empties the extracted-CBZ chapter cache each launch.
    static let clearChapterCacheOnLaunch = Key("download.clearChapterCacheOnLaunch", false)

    // MARK: Updates
    /// When the Updates tab was last open (seconds since 1970); newer chapters count in its badge.
    static let updatesLastSeen = Key("updates.lastSeen", 0.0)
    /// A `TriState` raw value: only bookmarked chapters (include), none of them (exclude), or all.
    static let updatesBookmarked = Key("updates.bookmarked", "off")
    /// `TriState` raw values for the other Updates filters.
    static let updatesDownloaded = Key("updates.downloaded", "off")
    static let updatesUnread = Key("updates.unread", "off")
    static let updatesStarted = Key("updates.started", "off")
    /// Shows the unseen-updates count on the Updates tab and the app icon.
    static let updatesBadge = Key("updates.badge", true)
    /// Hours between automatic library updates; 0 is off. iOS decides the exact time.
    static let autoUpdateInterval = Key("updates.autoInterval", 0)
    /// Automatic updates run only while charging (a processing task instead of an app refresh).
    static let autoUpdateOnlyCharging = Key("updates.onlyCharging", false)
    static let updateSkipUnread = Key("updates.skipUnread", false)
    static let updateSkipUnstarted = Key("updates.skipUnstarted", false)
    static let updateSkipCompleted = Key("updates.skipCompleted", true)
    /// Refreshes only titles whose next release is predicted to be near.
    static let updateSmart = Key("updates.smart", true)
    /// Library updates also re-fetch details and cover.
    static let updateRefreshMetadata = Key("updates.refreshMetadata", false)
    /// A metadata refresh also renames the title to the source's current one; off keeps the name you have.
    static let updateMatchTitles = Key("updates.matchTitles", true)
    /// A notification for each title with new chapters.
    static let updateNotify = Key("updates.notify", true)
    /// Notifications say "New chapters" without the title.
    static let updateHideNotificationContent = Key("updates.hideNotificationContent", false)
}

extension Pref {
    // MARK: App updates
    /// Looks for a newer Ahoge release on GitHub when the app opens (at most once a day).
    static let checkUpdates = Key("app.checkUpdates", true)
    /// The release version the user chose to skip.
    static let skippedVersion = Key("app.skippedVersion", "")
    /// When the app last looked for a release (seconds since 1970).
    static let lastUpdateCheck = Key("app.lastUpdateCheck", 0.0)
}

extension Pref {
    // MARK: Onboarding
    /// The welcome guide was shown (or skipped). Device state, not backed up.
    static let onboarded = Key("app.onboarded", false)
}
