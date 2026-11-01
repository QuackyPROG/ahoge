import SwiftUI

struct ErrorStateView: View {
    let error: Error
    let retry: () -> Void
    var openWeb: ((String) -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.secondary)
            Text(error.localizedDescription).font(.callout).multilineTextAlignment(.center)
            HStack {
                Button("Retry", action: retry).buttonStyle(.bordered)
                if case .cloudflare(let url)? = error as? SourceError, let openWeb {
                    Button("Open web view") { openWeb(url) }.buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
