import SwiftUI

/// Checks GitHub for a newer release and holds the one to show.
@MainActor
final class UpdateCenter: ObservableObject {
    static let shared = UpdateCenter()

    /// A newer release waiting in the update sheet.
    @Published var available: ReleaseInfo?
    @Published private(set) var checking = false
    /// The current version's release notes ("What's new"); nil until loaded or when it has none.
    @Published private(set) var currentNotes: ReleaseInfo?
    /// A message after a manual check that found nothing (or failed).
    @Published var manualResult: String?

    private let checker = ReleaseChecker(transport: URLSessionTransport.shared)
    private let day: TimeInterval = 24 * 60 * 60

    /// On launch: at most once a day, and only when the setting is on.
    func checkIfDue(now: Date = Date()) async {
        guard Pref.checkUpdates.value(), !checking else { return }
        guard now.timeIntervalSince1970 - Pref.lastUpdateCheck.value() >= day else { return }
        Pref.lastUpdateCheck.set(now.timeIntervalSince1970)
        if let release = try? await checker.latest(current: AppInfo.shortVersion, skipping: Pref.skippedVersion.value()) {
            available = release
        }
    }

    /// About → Check for updates: ignores the day limit and a skipped version, and always answers.
    func checkNow() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        do {
            if let release = try await checker.latest(current: AppInfo.shortVersion) {
                available = release
            } else {
                manualResult = "Ahoge \(AppInfo.shortVersion) is the latest version."
            }
        } catch {
            manualResult = "Could not check for updates: \(error.localizedDescription)"
        }
    }

    func skip(_ release: ReleaseInfo) {
        Pref.skippedVersion.set(release.version)
        available = nil
    }

    func loadCurrentNotes() async {
        currentNotes = try? await checker.release(for: AppInfo.shortVersion)
    }
}

/// The update sheet: release notes, Download (opens the release page) and Skip this version.
struct UpdateSheet: View {
    let release: ReleaseInfo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ReleaseNotesText(notes: release.notes)
                .navigationTitle("Ahoge \(release.version)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Download") {
                            openURL(release.pageURL)
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Skip this version") {
                            UpdateCenter.shared.skip(release)
                            dismiss()
                        }
                    }
                }
        }
    }
}

/// "What's new": the release notes of the version you are running.
struct WhatsNewView: View {
    @ObservedObject private var center = UpdateCenter.shared
    @State private var loaded = false

    var body: some View {
        Group {
            if let release = center.currentNotes {
                ReleaseNotesText(notes: release.notes)
            } else if loaded {
                ContentUnavailableView("No release notes", systemImage: "doc.text", description: Text("There are no notes for version \(AppInfo.shortVersion) yet."))
            } else {
                ProgressView()
            }
        }
        .navigationTitle("What's new")
        .navigationBarTitleDisplayMode(.inline)
        .themedScreen()
        .task {
            await center.loadCurrentNotes()
            loaded = true
        }
    }
}

/// GitHub's release notes are Markdown; headings and lists show as plain lines, links and emphasis render.
struct ReleaseNotesText: View {
    let notes: String

    var body: some View {
        ScrollView {
            Text(rendered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }

    private var rendered: AttributedString {
        let text = notes.isEmpty ? "No release notes." : notes
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
