import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Text("Library")
                .tabItem { Label("Library", systemImage: "books.vertical") }
            Text("Browse")
                .tabItem { Label("Browse", systemImage: "safari") }
            Text("More")
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
    }
}
