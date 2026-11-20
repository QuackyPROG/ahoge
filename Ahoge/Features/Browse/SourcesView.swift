import SwiftUI

struct SourcesView: View {
    @EnvironmentObject private var store: ExtensionStore
    @AppStorage(Pref.lastUsedSource.name) private var lastUsed = ""
    @State private var pinned = Pref.pinnedSources.value()
    @State private var incognito = Pref.incognitoSources.value()
    @State private var visibility = SourceVisibility.current()
    @State private var globalQuery = ""
    @State private var searching = false
    @State private var openingLink = false
    @State private var linkText = ""
    @State private var linkFailed = false
    @EnvironmentObject private var navigator: AppNavigator

    var body: some View {
        // Sources switched off in the filter screen are left out everywhere here.
        let installed = store.installed.filter { visibility.shows($0) }
        let pinnedItems = pinned.compactMap { id in installed.first { $0.id == id } }
        // Pinned sources move to their own section; the rest stay grouped by language.
        let rest = installed.filter { !pinned.contains($0.id) }
        let groups = Dictionary(grouping: rest, by: \.lang).sorted { $0.key < $1.key }
        List {
            // Always there: the folder of files on this device.
            Section {
                NavigationLink(value: Route.source(LocalSource.id)) {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .frame(width: 32, height: 32)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        Text("Local")
                    }
                }
            }
            .themedRows()
            if installed.isEmpty {
                if store.installed.isEmpty {
                    ContentUnavailableView("No sources", systemImage: "puzzlepiece.extension", description: Text("Install sources from Extensions."))
                } else {
                    ContentUnavailableView("All sources are hidden", systemImage: "line.3.horizontal.decrease.circle", description: Text("Turn them back on from the filter button."))
                }
            }
            if let recent = installed.first(where: { $0.id == lastUsed }) {
                Section("Last used") { row(recent) }
                    .themedRows()
            }
            if !pinnedItems.isEmpty {
                Section("Pinned") {
                    ForEach(pinnedItems) { row($0) }
                }
                .themedRows()
            }
            ForEach(groups, id: \.key) { lang, items in
                Section(Locale.current.localizedString(forLanguageCode: lang) ?? lang.uppercased()) {
                    ForEach(items.sorted { $0.name < $1.name }) { row($0) }
                }
                .themedRows()
            }
        }
        .themedScreen()
        .searchable(text: $globalQuery, isPresented: $searching, prompt: "Search all sources")
        .onSubmit(of: .search) {
            let query = globalQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return }
            navigator.push(.globalSearch(query))
            // Back on Sources shows the list again, not the old query.
            globalQuery = ""
            searching = false
        }
        .alert("Open link", isPresented: $openingLink) {
            TextField("https://…", text: $linkText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button("Open") { openLink() }
                .disabled(linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste the web address of a title on one of your sources.")
        }
        .alert("No source matches this link", isPresented: $linkFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Install the source for that site first.")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    linkText = ""
                    openingLink = true
                } label: { Image(systemName: "link") }
                    .accessibilityLabel("Open link")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SourceFilterView() } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                    .accessibilityLabel("Filter sources")
            }
        }
        // Back from the filter or details screens, which change these settings.
        .onAppear {
            visibility = .current()
            incognito = Pref.incognitoSources.value()
        }
    }

    private func row(_ item: InstalledSource) -> some View {
        let isPinned = pinned.contains(item.id)
        let isIncognito = incognito.contains(item.id)
        return NavigationLink(value: Route.source(item.id)) {
            HStack(spacing: 12) {
                RemoteImage(url: item.iconURL ?? "")
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(item.name)
                if isPinned || isIncognito { Spacer() }
                if isIncognito {
                    Image(systemName: "eyeglasses").font(.caption).foregroundStyle(.secondary).accessibilityLabel("Incognito")
                }
                if isPinned {
                    Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary).accessibilityLabel("Pinned")
                }
            }
        }
        .contextMenu {
            Button(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin") { togglePin(item.id) }
            Button(isIncognito ? "Turn off incognito" : "Read in incognito", systemImage: "eyeglasses") { toggleIncognito(item.id) }
            Button("Extension details", systemImage: "info.circle") { navigator.push(.extensionDetails(item.id)) }
        }
    }

    /// Matches a pasted web address (or `ahoge://` link) against the installed sources' sites.
    private func openLink() {
        let text = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), let link = DeepLinkResolver.resolve(url, sources: store.installed) else {
            linkFailed = true
            return
        }
        switch link {
        case .manga(let sourceId, let path): navigator.push(.manga(MangaRef(sourceId: sourceId, url: path, title: "", cover: "")))
        case .search(let query): navigator.push(.globalSearch(query))
        case .addRepo: navigator.open(link)
        }
    }

    private func togglePin(_ id: String) {
        if let index = pinned.firstIndex(of: id) { pinned.remove(at: index) } else { pinned.append(id) }
        Pref.pinnedSources.set(pinned)
    }

    /// Reading this source saves no progress or history, whatever the global incognito switch says.
    private func toggleIncognito(_ id: String) {
        if let index = incognito.firstIndex(of: id) { incognito.remove(at: index) } else { incognito.append(id) }
        Pref.incognitoSources.set(incognito)
    }
}
