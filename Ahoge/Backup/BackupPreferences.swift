import Foundation

extension Pref {
    /// The settings a backup carries. A new `Pref` key that should survive a restore goes here.
    /// Left out on purpose: the default category (an id that differs per device) and timestamps.
    static let backupNames: [String] = [
        libraryShelf.name, librarySort.name, libraryContinueButton.name,
        browseHideInLibrary.name, pinnedSources.name,
        readerMode.name, readerBackground.name, readerShowPageNumber.name, readerKeepScreenOn.name, readerDim.name,
        readerTapZones.name, readerInvertTaps.name, readerWebtoonPadding.name, readerWebtoonGap.name,
        theme.name, themeMode.name, pureBlack.name,
        secureScreen.name, autoBackupInterval.name, autoBackupKeep.name,
    ]
}

extension PreferenceValue {
    /// A stored value of a type backups can hold; nil for anything else.
    init?(stored object: Any?) {
        switch object {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { self = .bool(number.boolValue) }
            else if CFNumberIsFloatType(number) { self = .double(number.doubleValue) }
            else { self = .int(number.intValue) }
        case let string as String: self = .string(string)
        case let strings as [String]: self = .strings(strings)
        default: return nil
        }
    }

    var stored: Any {
        switch self {
        case .bool(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .string(let value): return value
        case .strings(let value): return value
        }
    }
}
