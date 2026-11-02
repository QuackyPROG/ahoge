import SwiftUI

struct LibraryToggleButton: View {
    let ref: MangaRef
    @EnvironmentObject private var repo: LibraryRepository

    var body: some View {
        let inLibrary = repo.manga(sourceId: ref.sourceId, url: ref.url)?.inLibrary ?? false
        Button(inLibrary ? "Remove from library" : "Add to library", systemImage: inLibrary ? "heart.slash" : "heart") {
            let manga = repo.upsert(sourceId: ref.sourceId, url: ref.url, title: ref.title, cover: ref.cover)
            repo.setInLibrary(manga, !inLibrary)
        }
    }
}
