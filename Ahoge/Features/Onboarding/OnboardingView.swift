import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

/// First launch: welcome, theme, the Ahoge Extensions repository, notifications, restoring a backup.
/// Every step can be skipped; More → Help → Welcome guide opens it again.
struct OnboardingView: View {
    let finish: () -> Void
    @EnvironmentObject private var repo: LibraryRepository
    @EnvironmentObject private var extensions: ExtensionStore
    @Environment(\.palette) private var palette
    @State private var step = Step.welcome
    @State private var working = false
    @State private var importing = false
    @State private var note: String?

    enum Step: Int, CaseIterable { case welcome, theme, repository, notifications, restore, done }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(step)
                .transition(.opacity)
            if let note {
                Text(note).font(.footnote).foregroundStyle(.secondary).padding(.horizontal).multilineTextAlignment(.center)
            }
            buttons
                .padding()
        }
        .background(palette.background.color.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.2), value: step)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url): Task { await restore(from: url) }
            case .failure(let error): note = error.localizedDescription
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            page("book.pages.fill", "Welcome to Ahoge", "A manga reader for iPhone and iPad. A few quick steps set it up. You can skip any of them.")
        case .theme:
            AppearanceView()
        case .repository:
            page("shippingbox.fill", "Get sources", "Ahoge has no sources of its own. Add the Ahoge Extensions repository to browse and install them. You can add other repositories later in More.")
        case .notifications:
            page("bell.badge.fill", "Stay up to date", "Allow notifications to hear about new chapters of the titles in your library.")
        case .restore:
            page("arrow.down.doc.fill", "Restore a backup?", "Bring your library back from an Ahoge backup, or a Mihon or Tachiyomi one.")
        case .done:
            page("checkmark.circle.fill", "You're set", "Find the library, updates and history in the tabs below. More has every setting.")
        }
    }

    private func page(_ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(palette.onPrimary.color)
                .frame(width: 88, height: 88)
                .background(palette.primary.color.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text(title).font(.title2.bold())
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
        }
    }

    private var buttons: some View {
        VStack(spacing: 8) {
            Button(action: primary) {
                Text(primaryTitle).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(working)
            if step != .welcome, step != .done {
                Button("Skip") { advance() }.disabled(working)
            }
        }
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Get started"
        case .theme: "Continue"
        case .repository: working ? "Adding…" : "Add Ahoge Extensions"
        case .notifications: "Allow notifications"
        case .restore: working ? "Restoring…" : "Choose a backup"
        case .done: "Start reading"
        }
    }

    private func primary() {
        switch step {
        case .welcome, .theme: advance()
        case .repository:
            working = true
            Task {
                defer { working = false }
                do {
                    try await extensions.addRepo(ExtensionStore.defaultRepoURL)
                    advance()
                } catch {
                    note = "Could not add the repository: \(error.localizedDescription)"
                }
            }
        case .notifications:
            Task {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                advance()
            }
        case .restore: importing = true
        case .done: finish()
        }
    }

    private func advance() {
        note = nil
        if let next = Step(rawValue: step.rawValue + 1) { step = next } else { finish() }
    }

    private func restore(from url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        working = true
        defer { working = false }
        do {
            let backup = try BackupService.load(try Data(contentsOf: url), sources: extensions.rows().map { $0.source })
            let report = await BackupService.restore(backup, into: repo, store: extensions, defaults: .standard)
            note = "\(report.restoredManga) title\(report.restoredManga == 1 ? "" : "s") restored."
            step = .done
        } catch {
            note = error.localizedDescription
        }
    }
}
