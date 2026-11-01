import SwiftUI
import WebKit

struct MoreView: View {
    @EnvironmentObject private var sources: SourceManager
    @State private var showRepos = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Extension repositories") { showRepos = true }
                }
                Section("Data") {
                    Button("Clear image cache") {
                        Task {
                            await ImageLoader.shared.clear()
                            message = "Image cache cleared."
                        }
                    }
                    Button("Clear cookies and website data", role: .destructive) {
                        Task {
                            SharedCookies.removeAll()
                            await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
                            sources.resetSessions()
                            message = "Cookies and website data cleared."
                        }
                    }
                }
                Section("About") {
                    LabeledContent("Version", value: AppInfo.version)
                    Link("Source code", destination: URL(string: "https://github.com/QuackyPROG/ahoge")!)
                    NavigationLink("Licenses") { LicensesView() }
                }
            }
            .navigationTitle("More")
            .sheet(isPresented: $showRepos) { NavigationStack { RepositoriesView() } }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}
