import SwiftUI

@main
struct AhogeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var extensions: ExtensionStore
    @StateObject private var sources: SourceManager
    @StateObject private var library: LibraryRepository
    @StateObject private var updater: LibraryUpdater
    @StateObject private var downloads: DownloadManager

    init() {
        let store = ExtensionStore()
        let sources = SourceManager(extensions: store)
        _extensions = StateObject(wrappedValue: store)
        _sources = StateObject(wrappedValue: sources)
        let library: LibraryRepository
        do {
            library = try LibraryRepository.open()
        } catch {
            fatalError("Could not open the library database: \(error)")
        }
        _library = StateObject(wrappedValue: library)
        if Pref.clearChapterCacheOnLaunch.value() {
            try? FileManager.default.removeItem(at: DownloadManager.defaultCache())
        }
        let downloads = DownloadManager(
            repo: library,
            sources: sources,
            transport: URLSessionTransport.shared,
            root: DownloadManager.defaultRoot(),
            cache: DownloadManager.defaultCache()
        )
        downloads.backgroundTransport = BackgroundTransport.shared
        let updater = LibraryUpdater()
        updater.downloads = downloads
        _downloads = StateObject(wrappedValue: downloads)
        _updater = StateObject(wrappedValue: updater)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(extensions)
                .environmentObject(sources)
                .environmentObject(library)
                .environmentObject(updater)
                .environmentObject(downloads)
        }
    }
}
