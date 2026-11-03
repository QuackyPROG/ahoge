import UIKit
import UserNotifications

/// UIKit callbacks SwiftUI has no modifier for.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Background tasks must be registered, and the notification delegate set, before launch finishes
    /// (a tap that launched the app is delivered to it).
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundRefresh.register()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// A tap on an update notification opens the title (or Updates).
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo as? [String: String] ?? [:]
        await MainActor.run { UpdateNotifier.handleTap(info) }
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
