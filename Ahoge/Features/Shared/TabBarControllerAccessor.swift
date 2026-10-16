// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI
import UIKit

/// A single associated delegate proxy per tab controller preserves SwiftUI's delegate.
struct TabBarControllerAccessor: UIViewControllerRepresentable {
    let onReselect: (Int) -> Void
    func makeUIViewController(context: Context) -> Probe { Probe(onReselect: onReselect) }
    func updateUIViewController(_ controller: Probe, context: Context) { controller.onReselect = onReselect; controller.attach() }
    final class Probe: UIViewController {
        var onReselect: (Int) -> Void
        init(onReselect: @escaping (Int) -> Void) { self.onReselect = onReselect; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); attach() }
        override func didMove(toParent parent: UIViewController?) { super.didMove(toParent: parent); DispatchQueue.main.async { [weak self] in self?.attach() } }
        func attach() {
            guard let tab = tabBarController else { return }
            if let proxy = objc_getAssociatedObject(tab, &DelegateProxy.key) as? DelegateProxy {
                proxy.onReselect = onReselect
                if tab.delegate !== proxy { proxy.original = tab.delegate; tab.delegate = proxy }
                return
            }
            let proxy = DelegateProxy()
            proxy.original = tab.delegate
            proxy.onReselect = onReselect
            objc_setAssociatedObject(tab, &DelegateProxy.key, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            tab.delegate = proxy
        }
    }
    final class DelegateProxy: NSObject, UITabBarControllerDelegate {
        static var key: UInt8 = 0
        weak var original: UITabBarControllerDelegate?
        var onReselect: ((Int) -> Void)?
        private var reselected = false
        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            reselected = tabBarController.selectedViewController === viewController
            return original?.tabBarController?(tabBarController, shouldSelect: viewController) ?? true
        }
        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            original?.tabBarController?(tabBarController, didSelect: viewController)
            if reselected { onReselect?(tabBarController.selectedIndex) }
            reselected = false
        }
        override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || original?.responds(to: selector) == true }
        override func forwardingTarget(for selector: Selector!) -> Any? { original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector) }
    }
}
