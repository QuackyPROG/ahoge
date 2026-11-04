import UIKit

/// Blurs every window while the app is not active, so the app switcher shows no library content.
/// Added to the windows themselves, not to SwiftUI, so it also covers the full-screen reader.
@MainActor
enum PrivacyShield {
    private static let tag = 0xA60E

    static func setVisible(_ visible: Bool) {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                let existing = window.viewWithTag(tag)
                if visible, existing == nil {
                    let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
                    blur.tag = tag
                    blur.frame = window.bounds
                    blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    window.addSubview(blur)
                } else if !visible {
                    existing?.removeFromSuperview()
                }
            }
        }
    }
}
