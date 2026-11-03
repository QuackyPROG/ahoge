import SwiftUI

struct LibraryToggleButton: View {
    let ref: MangaRef
    /// Called after adding when the user should pick categories ("Always ask").
    var chooseCategories: (LibraryManga) -> Void = { _ in }
    @EnvironmentObject private var repo: LibraryRepository
    @AppStorage(Pref.libraryDefaultCategory.name) private var defaultCategory = LibraryPrefs.alwaysAsk

    var body: some View {
        let inLibrary = repo.manga(sourceId: ref.sourceId, url: ref.url)?.inLibrary ?? false
        Button(inLibrary ? "Remove from library" : "Add to library", systemImage: inLibrary ? "heart.slash" : "heart") {
            let manga = repo.upsert(sourceId: ref.sourceId, url: ref.url, title: ref.title, cover: ref.cover)
            if inLibrary {
                repo.setInLibrary(manga, false)
            } else if repo.addToLibrary(manga, defaultCategory: defaultCategory) {
                chooseCategories(manga)
            }
        }
    }
}
