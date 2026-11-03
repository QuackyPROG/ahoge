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
    static let librarySort = Key("library.sort", "Title")
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

    // MARK: Reader
    static let readerMode = Key("reader.mode.default", "webtoon")
    static let readerBackground = Key("reader.background", "black")
    static let readerShowPageNumber = Key("reader.showPageNumber", true)
    static let readerKeepScreenOn = Key("reader.keepScreenOn", true)
    static let readerDim = Key("reader.dim", 0.0)
    static let readerTapZones = Key("reader.tapZones", true)
    static let readerInvertTaps = Key("reader.invertTaps", false)
    static let readerWebtoonPadding = Key("reader.webtoonPadding", 0.0)
    static let readerWebtoonGap = Key("reader.webtoonGap", false)

    // MARK: Appearance
    static let theme = Key("ui.theme", "standard")
    static let themeMode = Key("ui.themeMode", "system")
    static let pureBlack = Key("ui.pureBlack", false)

    // MARK: Privacy
    /// Covers the app in the app switcher.
    static let secureScreen = Key("security.secureScreen", false)

    // MARK: Backup
    /// Hours between automatic backups; 0 is off.
    static let autoBackupInterval = Key("backup.autoInterval", 0)
    /// How many automatic backups to keep in Documents/Backups.
    static let autoBackupKeep = Key("backup.autoKeep", 4)
    /// When the last automatic backup was made (seconds since 1970).
    static let autoBackupLast = Key("backup.autoLast", 0.0)

    // MARK: Updates
    /// When the Updates tab was last open (seconds since 1970); newer chapters count in its badge.
    static let updatesLastSeen = Key("updates.lastSeen", 0.0)
}
