import SwiftUI
import UniformTypeIdentifiers

/// The library as a CSV file: title, author, artist, source, URL.
enum LibraryCSV {
    /// `sourceInfo` gives a source's display name and website address by id.
    static func make(_ manga: [LibraryManga], sourceInfo: (String) -> (name: String, baseUrl: String)?) -> String {
        var lines = ["Title,Author,Artist,Source,URL"]
        for title in manga.sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) {
            let info = sourceInfo(title.sourceId)
            let link = info.map { title.webURL(baseUrl: $0.baseUrl) } ?? title.url
            lines.append([title.title, title.author, title.artist, info?.name ?? title.sourceId, link].map(field).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Quotes a field that holds a comma, quote or line break.
    static func field(_ text: String) -> String {
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
