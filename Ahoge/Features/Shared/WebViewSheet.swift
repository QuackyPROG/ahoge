import SwiftUI
import WebKit

struct WebTarget: Identifiable, Hashable {
    let url: String
    var id: String { url }
}

/// In-app browser used for Cloudflare checks and "open in web view". Done copies its cookies to sources.
struct WebViewSheet: View {
    let target: WebTarget
    @EnvironmentObject private var sources: SourceManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebView(url: target.url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(URL(string: target.url)?.host ?? "Web")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { Task { await finish() } }
                    }
                }
        }
    }

    private func finish() async {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        sources.importWebCookies(cookies)
        dismiss()
    }
}

private struct WebView: UIViewRepresentable {
    let url: String

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        // Cloudflare binds its clearance cookie to the User-Agent, so match the sources' UA.
        view.customUserAgent = HTTPClient.defaultUserAgent
        if let target = URL(string: url) { view.load(URLRequest(url: target)) }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}
