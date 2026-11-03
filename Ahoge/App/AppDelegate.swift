import UIKit

/// UIKit callbacks SwiftUI has no modifier for.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Background tasks must be registered before launch finishes.
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundRefresh.register()
        return true
    }

    /// iOS wakes the app when background page downloads finish; the session must be told when its
    /// events are handled so the system can snapshot and suspend the app again.
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        if identifier == BackgroundTransport.identifier {
            BackgroundTransport.shared.setEventsCompletionHandler(completionHandler)
        } else {
            completionHandler()
        }
    }

    /// The reader's rotation lock (`OrientationLock`); every orientation otherwise.
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}
