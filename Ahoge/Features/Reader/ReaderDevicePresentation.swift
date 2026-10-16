import SwiftUI
import UIKit

// Reader-scoped native system requests; restore the pre-reader state on teardown.
struct ReaderDevicePresentation: UIViewControllerRepresentable {
    let orientation: ReaderOrientation
    let keepAwake: Bool
    func makeUIViewController(context: Context) -> ReaderDeviceController { ReaderDeviceController() }
    func updateUIViewController(_ controller: ReaderDeviceController, context: Context) {
        controller.orientation = orientation
        controller.keepAwake = keepAwake
        controller.apply()
    }
    static func dismantleUIViewController(_ controller: ReaderDeviceController, coordinator: ()) { controller.stop() }
}
@MainActor
final class ReaderDeviceController: UIViewController {
    var orientation: ReaderOrientation = .system
    var keepAwake = true
    private var previousIdleTimer: Bool?
    private var previousOrientation: UIInterfaceOrientation?
    private weak var readerScene: UIWindowScene?
    private var active = false
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: UIDevice.orientationDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(suspend), name: UIApplication.willResignActiveNotification, object: nil)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if previousIdleTimer == nil {
            previousIdleTimer = UIApplication.shared.isIdleTimerDisabled
            readerScene = view.window?.windowScene
            previousOrientation = readerScene?.interfaceOrientation
        }
        active = true
        apply()
    }
    @objc private func refresh() { apply() }
    @objc private func suspend() {
        if let previousIdleTimer { UIApplication.shared.isIdleTimerDisabled = previousIdleTimer }
    }
    func apply() {
        guard active, UIApplication.shared.applicationState == .active else { return }
        UIApplication.shared.isIdleTimerDisabled = keepAwake
        guard let scene = readerScene ?? view.window?.windowScene else { return }
        let mask: UIInterfaceOrientationMask
        switch orientation {
        case .system: mask = .all
        case .portrait: mask = .portrait
        case .landscape: mask = .landscape
        }
        scene.windows.first(where: { $0.isKeyWindow })?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
    }
    func stop() {
        guard active else { return }
        active = false
        NotificationCenter.default.removeObserver(self)
        if let previousIdleTimer { UIApplication.shared.isIdleTimerDisabled = previousIdleTimer }
        if orientation != .system, let scene = readerScene ?? view.window?.windowScene, let previousOrientation {
            let mask: UIInterfaceOrientationMask
            switch previousOrientation {
            case .portrait: mask = .portrait
            case .portraitUpsideDown: mask = .portraitUpsideDown
            case .landscapeLeft: mask = .landscapeLeft
            case .landscapeRight: mask = .landscapeRight
            default: mask = .all
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        }
    }
}
