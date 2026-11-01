import SwiftData
import SwiftUI

struct LibraryToggleButton: View {
    let ref: MangaRef
    @Environment(\.modelContext) private var context

    var body: some View {
        let repo = LibraryRepository(context: context)
        let inLibrary = repo.manga(sourceId: ref.sourceId, url: ref.url)?.inLibrary ?? false
        Button(inLibrary ? "Remove from library" : "Add to library", systemImage: inLibrary ? "heart.slash" : "heart") {
            let manga = repo.upsert(sourceId: ref.sourceId, url: ref.url, title: ref.title, cover: ref.cover)
            repo.setInLibrary(manga, !inLibrary)
        }
    }
}
