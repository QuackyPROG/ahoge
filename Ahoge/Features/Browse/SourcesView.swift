import SwiftUI

struct SourcesView: View {
    @EnvironmentObject private var store: ExtensionStore

    var body: some View {
        let groups = Dictionary(grouping: store.installed, by: \.lang).sorted { $0.key < $1.key }
        List {
            if store.installed.isEmpty {
                ContentUnavailableView("No sources", systemImage: "puzzlepiece.extension", description: Text("Install sources from Extensions."))
            }
            ForEach(groups, id: \.key) { lang, items in
                Section(Locale.current.localizedString(forLanguageCode: lang) ?? lang.uppercased()) {
                    ForEach(items.sorted { $0.name < $1.name }) { item in
                        NavigationLink(value: Route.source(item.id)) {
                            HStack(spacing: 12) {
                                RemoteImage(url: item.iconURL ?? "")
                                    .frame(width: 32, height: 32)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Text(item.name)
                            }
                        }
                    }
                }
            }
        }
    }
}
