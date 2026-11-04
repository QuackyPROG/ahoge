import Foundation

/// A page the reader shows: a downloaded file, or a page from the source.
enum ReaderPage: Equatable {
    case local(URL)
    case remote(SourcePage)

    /// What the reader's image views load; a file URL needs no headers (`ImageLoader` reads it from disk).
    var sourcePage: SourcePage {
        switch self {
        case .local(let url): SourcePage(url: url.absoluteString, headers: [:])
        case .remote(let page): page
        }
    }
}

/// Where the reader gets a chapter's pages: downloaded files first, the source otherwise. A
/// downloaded chapter stays readable after its source is uninstalled (Mihon allows this).
@MainActor
struct PageProvider {
    let sources: SourceManager
    let downloads: DownloadManager

    func pages(for chapter: ChapterRecord) async throws -> [ReaderPage] {
        if let files = downloads.localPages(chapter.key) { return files.map(ReaderPage.local) }
        return try await sources.source(chapter.sourceId).pages(url: chapter.url).map(ReaderPage.remote)
    }
}
