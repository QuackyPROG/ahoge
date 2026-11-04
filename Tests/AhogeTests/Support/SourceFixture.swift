import Foundation
@testable import Ahoge

/// A real `SourceManager` with one installed source, `en.test`, whose `pages(url)` returns
/// `https://img.test<url>/1.jpg` … `/<pageCount>.jpg`, each with a Referer header.
@MainActor
enum SourceFixture {
    static let sourceId = "en.test"

    static func extensions(pageCount: Int = 3) throws -> ExtensionStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let scripts = directory.appendingPathComponent("scripts")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        let script = """
        var source = {
          pages: async function (url) {
            var pages = [];
            for (var i = 1; i <= \(pageCount); i++) {
              pages.push({ url: "https://img.test" + url + "/" + i + ".jpg", headers: { Referer: "https://img.test/" } });
            }
            return pages;
          }
        };
        """
        try Data(script.utf8).write(to: scripts.appendingPathComponent("\(sourceId).js"))
        let state = """
        {"repos":[],"installed":[{"id":"\(sourceId)","repoURL":"https://r.test/index.json","name":"Test","lang":"en",
        "version":"1.0.0","nsfw":false,"baseUrl":"https://img.test","sha256":"\(Data(script.utf8).sha256Hex)"}]}
        """
        try Data(state.utf8).write(to: directory.appendingPathComponent("state.json"))
        return ExtensionStore(directory: directory, client: RepoClient(transport: StubTransport.text("", status: 500)))
    }

    /// A library title of `en.test` with chapters /c/1 … /c/<count> (the highest number is newest).
    static func manga(in repo: LibraryRepository, chapters count: Int) -> LibraryManga {
        let manga = repo.upsert(sourceId: sourceId, url: "/m", title: "Manga", cover: "")
        repo.setInLibrary(manga, true)
        repo.applyChapters(
            (1...count).reversed().map { SourceChapter(url: "/c/\($0)", name: "Ch \($0)", number: Double($0), date: nil, scanlator: nil) },
            to: manga
        )
        return manga
    }
}

extension LibraryManga {
    /// The chapter with URL `/c/<number>`.
    func chapter(_ number: Int) -> ChapterRecord {
        chapters.first { $0.url == "/c/\(number)" }!
    }
}
