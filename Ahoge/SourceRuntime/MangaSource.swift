import Foundation

/// What the app asks of a source: a script from an extension (`ScriptSource`) or the folder
/// of files on this device (`LocalSource`). The browse, reader, downloader and updater only see this.
protocol MangaSource: AnyObject {
    /// Whether the source has a settings screen.
    var hasPreferences: Bool { get }

    func popular(page: Int) async throws -> MangaListPage
    func latest(page: Int) async throws -> MangaListPage
    func search(query: String, page: Int) async throws -> MangaListPage
    func search(query: String, page: Int, filters: FilterState) async throws -> MangaListPage
    func filters() async throws -> [SourceFilter]
    func preferences() async throws -> [SourcePreference]
    func details(url: String) async throws -> MangaDetails
    func chapters(url: String) async throws -> [SourceChapter]
    func pages(url: String) async throws -> [SourcePage]
}
