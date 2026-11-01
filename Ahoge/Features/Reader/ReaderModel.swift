import Foundation

@MainActor
final class ReaderModel: ObservableObject {
    struct Section: Identifiable {
        let chapter: ChapterRecord
        let pages: [SourcePage]
        var id: String { chapter.url }
    }

    let sourceId: String
    let manga: LibraryManga
    @Published private(set) var sections: [Section] = []
    @Published private(set) var error: Error?
    @Published private(set) var isLoadingNext = false
    @Published private(set) var currentChapter: ChapterRecord
    @Published private(set) var currentPage = 0

    init(sourceId: String, manga: LibraryManga, start: ChapterRecord) {
        self.sourceId = sourceId
        self.manga = manga
        currentChapter = start
    }

    var currentSection: Section? { sections.first { $0.id == currentChapter.url } }

    /// The next chapter to read: the closest newer one (lower sourceOrder).
    func chapter(after chapter: ChapterRecord) -> ChapterRecord? {
        manga.chapters.filter { $0.sourceOrder < chapter.sourceOrder }.max { $0.sourceOrder < $1.sourceOrder }
    }

    func chapter(before chapter: ChapterRecord) -> ChapterRecord? {
        manga.chapters.filter { $0.sourceOrder > chapter.sourceOrder }.min { $0.sourceOrder < $1.sourceOrder }
    }

    /// Shows only `chapter`, replacing what was loaded.
    func open(_ chapter: ChapterRecord, manager: SourceManager) async {
        error = nil
        sections = []
        currentChapter = chapter
        currentPage = 0
        do {
            let pages = try await manager.source(sourceId).pages(url: chapter.url)
            sections = [Section(chapter: chapter, pages: pages)]
        } catch {
            self.error = error
        }
    }

    func pageAppeared(_ section: Section, index: Int, repo: LibraryRepository, manager: SourceManager) {
        currentChapter = section.chapter
        currentPage = index
        repo.saveProgress(section.chapter, page: index, pageCount: section.pages.count)
        for page in section.pages.dropFirst(index + 1).prefix(4) {
            Task { await ImageLoader.shared.prefetch(page.url, headers: page.headers) }
        }
        let isLastPage = index == section.pages.count - 1
        if isLastPage, section.id == sections.last?.id, !isLoadingNext, let next = chapter(after: section.chapter) {
            Task { await append(next, manager: manager) }
        }
    }

    private func append(_ chapter: ChapterRecord, manager: SourceManager) async {
        isLoadingNext = true
        defer { isLoadingNext = false }
        do {
            let pages = try await manager.source(sourceId).pages(url: chapter.url)
            if !sections.contains(where: { $0.id == chapter.url }) {
                sections.append(Section(chapter: chapter, pages: pages))
            }
        } catch {
            self.error = error
        }
    }
}
