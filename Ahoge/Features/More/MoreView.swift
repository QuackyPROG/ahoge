import SwiftUI
import WebKit

struct MoreView: View {
    @EnvironmentObject private var sources: SourceManager
    @Environment(\.palette) private var palette
    @State private var showRepos = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 6) {
                        Image(systemName: "book.pages.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(palette.onPrimary.color)
                            .frame(width: 72, height: 72)
                            .background(palette.primary.color.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Text(AppInfo.name).font(.title2.bold())
                        Text("Version \(AppInfo.version)").font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                Section {
                    NavigationLink { AppearanceView() } label: {
                        Label { Text("Appearance") } icon: { SettingsIcon(systemName: "paintpalette.fill", color: .purple) }
                    }
                    Button { showRepos = true } label: {
                        Label { Text("Extension repositories").foregroundStyle(.primary) } icon: { SettingsIcon(systemName: "shippingbox.fill", color: .orange) }
                    }
                }
                .themedRows()

                Section("Data") {
                    Button {
                        Task {
                            await ImageLoader.shared.clear()
                            message = "Image cache cleared."
                        }
                    } label: {
                        Label { Text("Clear image cache").foregroundStyle(.primary) } icon: { SettingsIcon(systemName: "photo.stack", color: .gray) }
                    }
                    Button(role: .destructive) {
                        Task {
                            SharedCookies.removeAll()
                            await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
                            sources.resetSessions()
                            message = "Cookies and website data cleared."
                        }
                    } label: {
                        Label { Text("Clear cookies and website data") } icon: { SettingsIcon(systemName: "trash.fill", color: .red) }
                    }
                }
                .themedRows()

                Section("About") {
                    Link(destination: URL(string: "https://github.com/QuackyPROG/ahoge")!) {
                        Label { Text("Source code").foregroundStyle(.primary) } icon: { SettingsIcon(systemName: "chevron.left.forwardslash.chevron.right", color: .gray) }
                    }
                    NavigationLink { LicensesView() } label: {
                        Label { Text("Licenses") } icon: { SettingsIcon(systemName: "doc.text.fill", color: .gray) }
                    }
                }
                .themedRows()
            }
            .navigationTitle("More")
            .themedScreen()
            .sheet(isPresented: $showRepos) { NavigationStack { RepositoriesView() } }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}
