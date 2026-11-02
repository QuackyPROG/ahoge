import SwiftUI

@main
struct AhogeApp: App {
    @StateObject private var extensions: ExtensionStore
    @StateObject private var sources: SourceManager
    @StateObject private var library: LibraryRepository
    @StateObject private var updater = LibraryUpdater()

    init() {
        let store = ExtensionStore()
        _extensions = StateObject(wrappedValue: store)
        _sources = StateObject(wrappedValue: SourceManager(extensions: store))
        let library: LibraryRepository
        do {
            library = try LibraryRepository.open()
        } catch {
            fatalError("Could not open the library database: \(error)")
        }
        _library = StateObject(wrappedValue: library)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(extensions)
                .environmentObject(sources)
                .environmentObject(library)
                .environmentObject(updater)
        }
    }
}
