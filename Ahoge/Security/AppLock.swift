import LocalAuthentication
import SwiftUI

/// The app lock: Face ID, Touch ID or the passcode over everything, including the full-screen reader.
/// The lock screen lives in its own window for that reason (the same idea as `PrivacyShield`).
@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()

    @Published private(set) var locked: Bool
    @Published private(set) var failed = false
    private var window: UIWindow?
    private var authenticating = false
    private var previous: ScenePhase = .background
    /// When the app left the foreground; nil while it is in front or unlocked this session.
    private var leftAt: Date?

    private init() {
        locked = Pref.requireUnlock.value()
    }

    /// Shows the lock window on launch when the lock is on.
    func start() {
        syncWindow()
        if locked { Task { await unlock() } }
    }

    func phaseChanged(to phase: ScenePhase, now: Date = Date()) {
        defer { previous = phase }
        guard Pref.requireUnlock.value() else {
            if locked { setLocked(false) }
            return
        }
        if phase == .active {
            if !locked, let leftAt, LockPolicy.needsUnlock(lastActive: leftAt, now: now, setting: Pref.lockAfter.value()) {
                setLocked(true)
            }
            leftAt = nil
            // Coming back from the system prompt (inactive) must not ask again.
            if locked, previous != .inactive { Task { await unlock() } }
        } else if previous == .active, !locked, !authenticating {
            leftAt = now
            // "Always": lock now, so the app switcher never shows content.
            if Pref.lockAfter.value() == 0 { setLocked(true) }
        }
    }

    func unlock() async {
        guard locked, !authenticating else { return }
        authenticating = true
        failed = false
        let ok = await Self.authenticate()
        authenticating = false
        if ok {
            leftAt = nil
            setLocked(false)
        } else {
            failed = true
        }
    }

    private func setLocked(_ value: Bool) {
        locked = value
        syncWindow()
    }

    private func syncWindow() {
        if locked {
            guard window == nil, let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
            let lockWindow = UIWindow(windowScene: scene)
            lockWindow.windowLevel = .alert + 1
            lockWindow.overrideUserInterfaceStyle = scene.windows.first?.overrideUserInterfaceStyle ?? .unspecified
            lockWindow.rootViewController = UIHostingController(rootView: LockView(lock: self))
            lockWindow.makeKeyAndVisible()
            window = lockWindow
        } else if let lockWindow = window {
            let scene = lockWindow.windowScene
            lockWindow.isHidden = true
            window = nil
            scene?.windows.first?.makeKey()
        }
    }

    /// Asks the device owner. With no passcode set there is nothing to ask, so the app opens rather than lock the user out.
    private static func authenticate() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Ahoge")) ?? false
    }
}

private struct LockView: View {
    @ObservedObject var lock: AppLock

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Ahoge is locked").font(.title3.weight(.semibold))
            Button("Unlock") { Task { await lock.unlock() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
