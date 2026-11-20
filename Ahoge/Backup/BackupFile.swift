import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in both Info.plists (UTExportedTypeDeclarations).
    static let ahogeBackup = UTType(exportedAs: "com.quackyprog.ahoge.backup", conformingTo: .data)
}

enum BackupFile {
    static let fileExtension = "ahbk"

    /// `ahoge_YYYY-MM-DD_HH-mm.ahbk` (`ahoge_auto_…` when automatic), in the device's time zone.
    static func name(at date: Date, calendar: Calendar = .current, automatic: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return "ahoge_\(automatic ? "auto_" : "")\(formatter.string(from: date)).\(fileExtension)"
    }

    /// Whether `name` is an automatic backup, the only kind rotation may delete.
    static func isAutomatic(_ name: String) -> Bool {
        name.range(of: #"^ahoge_auto_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}\.ahbk$"#, options: .regularExpression) != nil
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
