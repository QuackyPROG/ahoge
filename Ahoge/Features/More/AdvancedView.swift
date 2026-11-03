import SwiftUI

/// Network identity and diagnostics.
struct AdvancedView: View {
    @AppStorage(Pref.customUserAgent.name) private var userAgent = Pref.customUserAgent.defaultValue
    @State private var logFile: URL?
    @State private var logError: String?

    var body: some View {
        List {
            Section {
                TextField(HTTPClient.builtInUserAgent, text: $userAgent, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(1...4)
                    .font(.footnote)
                if !userAgent.isEmpty {
                    Button("Use the built-in user agent", role: .destructive) { userAgent = "" }
                }
            } header: {
                Text("User agent")
            } footer: {
                Text("Sent to sources, images and downloads. Some sites tie their Cloudflare clearance to it, so clear cookies after changing it.")
            }
            .themedRows()

            Section {
                if let logFile {
                    ShareLink(item: logFile) {
                        Label { Text("Share logs").foregroundStyle(.primary) } icon: { SettingsIcon(systemName: "square.and.arrow.up.fill", color: .blue) }
                    }
                } else {
                    Button(action: prepareLogs) {
                        Label { Text("Prepare logs").foregroundStyle(.primary) } icon: { SettingsIcon(systemName: "doc.plaintext.fill", color: .blue) }
                    }
                }
            } footer: {
                Text(logError ?? "The last 500 lines Ahoge logged since it opened. They can name the titles and sources you used.")
            }
            .themedRows()
        }
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
        .themedScreen()
    }

    private func prepareLogs() {
        do {
            logFile = try AppLog.exportFile()
            logError = nil
        } catch {
            logError = "Could not read the log: \(error.localizedDescription)"
        }
    }
}
