import SwiftUI

enum AppTab: Hashable {
    case library, updates, history, browse, more
}

/// Asks the interface to go somewhere from outside a view: a notification tap, and later deep links.
/// RootView follows `tab`; the Library tab consumes `pendingRoute` and pushes it.
@MainActor
final class AppNavigator: ObservableObject {
    /// A singleton because system callbacks (notification taps) have no view to reach it from.
    static let shared = AppNavigator()

    @Published var tab: AppTab = .library
    @Published var pendingRoute: Route?

    /// Shows `route` on top of the Library tab.
    func open(_ route: Route) {
        tab = .library
        pendingRoute = route
    }
}
