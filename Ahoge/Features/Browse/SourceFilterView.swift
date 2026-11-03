import SwiftUI

/// Mihon's source filter: switch whole languages or single sources off. Hidden sources stay
/// installed and keep their library titles; they leave Sources and global search only.
struct SourceFilterView: View {
    @EnvironmentObject private var store: ExtensionStore
    @State private var disabledSources = Set(Pref.disabledSources.value())
    @State private var disabledLanguages = Set(Pref.disabledLanguages.value())
    @AppStorage(Pref.browseContentFilter.name) private var content = ContentFilter.all.rawValue

    var body: some View {
        let groups = Dictionary(grouping: store.installed, by: \.lang).sorted { $0.key < $1.key }
        List {
            Section {
                Picker("Content", selection: $content) {
                    ForEach(ContentFilter.allCases) { Text($0.title).tag($0.rawValue) }
                }
            } footer: {
                Text("Uses the 18+ flag from the extension repository. Also applies to sources not yet installed in Extensions.")
            }
            .themedRows()
            ForEach(groups, id: \.key) { lang, items in
                Section {
                    Toggle(Self.languageName(lang), isOn: languageBinding(lang))
                        .font(.headline)
                    if !disabledLanguages.contains(lang) {
                        ForEach(items.sorted { $0.name < $1.name }) { item in
                            Toggle(isOn: sourceBinding(item.id)) {
                                HStack(spacing: 10) {
                                    RemoteImage(url: item.iconURL ?? "")
                                        .frame(width: 28, height: 28)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    Text(item.name)
                                    if item.nsfw { Text("18+").font(.caption2.bold()).foregroundStyle(.red) }
                                }
                            }
                        }
                    }
                }
                .themedRows()
            }
        }
        .navigationTitle("Filter sources")
        .navigationBarTitleDisplayMode(.inline)
        .themedScreen()
    }

    static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    private func languageBinding(_ lang: String) -> Binding<Bool> {
        Binding(
            get: { !disabledLanguages.contains(lang) },
            set: { on in
                if on { disabledLanguages.remove(lang) } else { disabledLanguages.insert(lang) }
                Pref.disabledLanguages.set(disabledLanguages.sorted())
            }
        )
    }

    private func sourceBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !disabledSources.contains(id) },
            set: { on in
                if on { disabledSources.remove(id) } else { disabledSources.insert(id) }
                Pref.disabledSources.set(disabledSources.sorted())
            }
        )
    }
}
