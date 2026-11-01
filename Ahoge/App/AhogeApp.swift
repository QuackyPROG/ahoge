import SwiftData
import SwiftUI

@main
struct AhogeApp: App {
    @StateObject private var extensions: ExtensionStore
    @StateObject private var sources: SourceManager
    private let container: ModelContainer

    init() {
        let store = ExtensionStore()
        _extensions = StateObject(wrappedValue: store)
        _sources = StateObject(wrappedValue: SourceManager(extensions: store))
        do {
            container = try ModelContainer(for: LibraryManga.self, ChapterRecord.self)
        } catch {
            fatalError("Could not open the library database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(extensions)
                .environmentObject(sources)
        }
        .modelContainer(container)
    }
}
