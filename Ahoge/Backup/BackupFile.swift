import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in both Info.plists (UTExportedTypeDeclarations).
    static let ahogeBackup = UTType(exportedAs: "com.quackyprog.ahoge.backup", conformingTo: .data)
}

enum BackupFile {
    static let fileExtension = "ahbk"

    /// `ahoge_YYYY-MM-DD_HH-mm.ahbk`, in the device's time zone.
    static func name(at date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return "ahoge_\(formatter.string(from: date)).\(fileExtension)"
    }
}

/// The bytes of a backup, for `fileExporter`.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.ahogeBackup] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
