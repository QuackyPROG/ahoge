import SwiftUI

/// Builds the services that need the library database, or keeps the error that stopped it, so a
/// database that cannot open shows an error screen instead of crashing the app.
@MainActor
final class AppServices: ObservableObject {
    struct Loaded {
        let library: LibraryRepository
        let downloads: DownloadManager
        let updater: LibraryUpdater
    }

    enum State {
        case loaded(Loaded)
        case failed(Error)
    }

    @Published private(set) var state: State
    private let extensions: ExtensionStore
    private let sources: SourceManager
    private let open: @MainActor () throws -> LibraryRepository

    init(extensions: ExtensionStore, sources: SourceManager, open: @escaping @MainActor () throws -> LibraryRepository = { try LibraryRepository.open() }) {
        self.extensions = extensions
        self.sources = sources
        self.open = open
        state = Self.make(extensions: extensions, sources: sources, open: open)
    }

    /// Tries again (Retry on the error screen).
    func load() {
        state = Self.make(extensions: extensions, sources: sources, open: open)
    }

    private static func make(extensions: ExtensionStore, sources: SourceManager, open: @MainActor () throws -> LibraryRepository) -> State {
        let library: LibraryRepository
        do {
            library = try open()
        } catch {
            AppLog.logger.error("Could not open the library database: \(error.localizedDescription, privacy: .public)")
            return .failed(error)
        }
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
        BackgroundRefresh.context = BackgroundRefresh.Context(repo: library, sources: sources, updater: updater, extensions: extensions)
        return .loaded(Loaded(library: library, downloads: downloads, updater: updater))
    }
}

/// Shown instead of the app when the library database cannot open.
struct DatabaseErrorView: View {
    let error: Error
    let retry: () -> Void
    @State private var logFile: URL?

    var body: some View {
        VStack(spacing: 12) {
            Text("Could not open the library").font(.headline)
            ErrorStateView(error: error, retry: {
                retry()
                prepareLogs()
            })
            if let logFile {
                ShareLink("Share logs", item: logFile)
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear(perform: prepareLogs)
    }

    private func prepareLogs() {
        logFile = try? AppLog.exportFile()
    }
}
