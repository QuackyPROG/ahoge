import SwiftUI

@main
struct AhogeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var extensions: ExtensionStore
    @StateObject private var sources: SourceManager
    @StateObject private var services: AppServices
    @StateObject private var navigator = AppNavigator.shared

    init() {
        let store = ExtensionStore()
        let sources = SourceManager(extensions: store)
        _extensions = StateObject(wrappedValue: store)
        _sources = StateObject(wrappedValue: sources)
        let services = AppServices(extensions: store, sources: sources)
        _services = StateObject(wrappedValue: services)
        Self.restoreNavigation(services)
    }

    var body: some Scene {
        WindowGroup {
            switch services.state {
            case .loaded(let loaded):
                RootView()
                    .environmentObject(extensions)
                    .environmentObject(sources)
                    .environmentObject(loaded.library)
                    .environmentObject(loaded.updater)
                    .environmentObject(loaded.downloads)
                    .environmentObject(navigator)
            case .failed(let error):
                DatabaseErrorView(error: error, retry: {
                    services.load()
                    Self.restoreNavigation(services)
                })
            }
        }
    }

    /// Reopens where the person was, once the library has opened.
    @MainActor
    private static func restoreNavigation(_ services: AppServices) {
        if case .loaded(let loaded) = services.state {
            AppNavigator.shared.restore(repo: loaded.library)
        }
    }
}
