import Foundation
import SwiftData

/// A manga the app has seen. `inLibrary` marks the ones saved to the Library (Mihon "favorite").
@Model
final class LibraryManga {
    @Attribute(.unique) var key: String
    var sourceId: String
    var url: String
    var title: String
    var coverUrl: String
    var author: String
    var artist: String
    var summary: String
    var genres: [String]
    var status: String
    var inLibrary: Bool
    var dateAdded: Date?
    var lastReadAt: Date?
    var lastChapterFetch: Date?
    @Relationship(deleteRule: .cascade, inverse: \ChapterRecord.manga) var chapters: [ChapterRecord] = []

    init(sourceId: String, url: String, title: String, coverUrl: String) {
        key = Self.makeKey(sourceId: sourceId, url: url)
        self.sourceId = sourceId
        self.url = url
        self.title = title
        self.coverUrl = coverUrl
        author = ""
        artist = ""
        summary = ""
        genres = []
        status = "unknown"
        inLibrary = false
    }

    static func makeKey(sourceId: String, url: String) -> String { sourceId + "\n" + url }

    /// Newest first, the order the source returned.
    var sortedChapters: [ChapterRecord] { chapters.sorted { $0.sourceOrder < $1.sourceOrder } }
    var unreadCount: Int { chapters.filter { !$0.read }.count }
    var ref: MangaRef { MangaRef(sourceId: sourceId, url: url, title: title, cover: coverUrl) }
}

@Model
final class ChapterRecord {
    @Attribute(.unique) var key: String
    var url: String
    var name: String
    var number: Double
    var dateUpload: Date?
    var scanlator: String?
    var read: Bool
    var lastPageRead: Int
    var sourceOrder: Int
    var manga: LibraryManga?

    init(sourceId: String, state: ChapterState) {
        key = LibraryManga.makeKey(sourceId: sourceId, url: state.url)
        url = state.url
        name = state.name
        number = state.number
        dateUpload = state.date
        scanlator = state.scanlator
        read = state.read
        lastPageRead = state.lastPageRead
        sourceOrder = state.sourceOrder
    }

    var state: ChapterState {
        ChapterState(url: url, name: name, number: number, date: dateUpload, scanlator: scanlator, read: read, lastPageRead: lastPageRead, sourceOrder: sourceOrder)
    }

    func apply(_ state: ChapterState) {
        name = state.name
        number = state.number
        dateUpload = state.date
        scanlator = state.scanlator
        read = state.read
        lastPageRead = state.lastPageRead
        sourceOrder = state.sourceOrder
    }
}

/// Navigation value for a manga (from a source listing or the library).
struct MangaRef: Hashable {
    let sourceId: String
    let url: String
    let title: String
    let cover: String
}
