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
    /// A chapter's pages from its source; tests replace it to decide when a lookup finishes.
    let remotePages: (ChapterRecord) async throws -> [SourcePage]

    init(sources: SourceManager, downloads: DownloadManager, remotePages: ((ChapterRecord) async throws -> [SourcePage])? = nil) {
        self.sources = sources
        self.downloads = downloads
        self.remotePages = remotePages ?? { chapter in try await sources.source(chapter.sourceId).pages(url: chapter.url) }
    }

    func pages(for chapter: ChapterRecord) async throws -> [ReaderPage] {
        if let files = await downloads.localPages(chapter.key) { return files.map(ReaderPage.local) }
        return try await remotePages(chapter).map(ReaderPage.remote)
    }
}
