import Combine
import Foundation
import GRDB

/// A manga the app has seen. `inLibrary` marks the ones saved to the Library (Mihon "favorite").
/// Change it only through `LibraryRepository`, which saves it and tells views.
final class LibraryManga: Identifiable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "manga"

    var key: String
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
    var notes: String
    /// File name in Application Support/covers; nil uses the source's cover.
    var customCover: String?
    /// Days between library updates; nil is smart, 0 is never.
    var updateInterval: Int?
    var nextUpdate: Date?
    /// Per-entry chapter sort/filter/display override bits.
    var chapterFlags: Int
    /// Loaded by `LibraryRepository` with the manga; not a column.
    var chapters: [ChapterRecord] = []

    enum CodingKeys: String, CodingKey {
        case key, sourceId, url, title, coverUrl, author, artist, summary, genres, status, inLibrary, dateAdded, lastReadAt, lastChapterFetch, notes, customCover, updateInterval, nextUpdate, chapterFlags
    }

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
        notes = ""
        chapterFlags = 0
    }

    static func makeKey(sourceId: String, url: String) -> String { sourceId + "\n" + url }

    var id: String { key }

    /// Newest first, the order the source returned.
    var sortedChapters: [ChapterRecord] { chapters.sorted { $0.sourceOrder < $1.sourceOrder } }
    /// Kept by `LibraryRepository` whenever chapters or read state change; not a column.
    private(set) var unreadCount = 0

    func refreshUnreadCount() { unreadCount = chapters.reduce(0) { $0 + ($1.read ? 0 : 1) } }
    var ref: MangaRef { MangaRef(sourceId: sourceId, url: url, title: title, cover: coverUrl) }
}

/// Observable so a row redraws when its read state changes; `LibraryRepository` sends the change.
final class ChapterRecord: ObservableObject, Identifiable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "chapter"

    var key: String
    var mangaKey: String
    var url: String
    var name: String
    var number: Double
    var dateUpload: Date?
    var scanlator: String?
    var read: Bool
    var lastPageRead: Int
    var sourceOrder: Int
    var dateFetch: Date?
    var bookmark: Bool
    /// Set by `LibraryRepository`; not a column.
    weak var manga: LibraryManga?

    enum CodingKeys: String, CodingKey {
        case key, mangaKey, url, name, number, dateUpload, scanlator, read, lastPageRead, sourceOrder, dateFetch, bookmark
    }

    init(manga: LibraryManga, state: ChapterState) {
        key = LibraryManga.makeKey(sourceId: manga.sourceId, url: state.url)
        mangaKey = manga.key
        url = state.url
        name = state.name
        number = state.number
        dateUpload = state.date
        scanlator = state.scanlator
        read = state.read
        lastPageRead = state.lastPageRead
        sourceOrder = state.sourceOrder
        dateFetch = state.dateFetch
        bookmark = false
        self.manga = manga
    }

    var id: String { key }

    var state: ChapterState {
        ChapterState(url: url, name: name, number: number, date: dateUpload, scanlator: scanlator, read: read, lastPageRead: lastPageRead, sourceOrder: sourceOrder, dateFetch: dateFetch)
    }

    func apply(_ state: ChapterState) {
        name = state.name
        number = state.number
        dateUpload = state.date
        scanlator = state.scanlator
        read = state.read
        lastPageRead = state.lastPageRead
        sourceOrder = state.sourceOrder
        dateFetch = state.dateFetch
    }
}

/// Navigation value for a manga (from a source listing or the library).
struct MangaRef: Hashable {
    let sourceId: String
    let url: String
    let title: String
    let cover: String
}
