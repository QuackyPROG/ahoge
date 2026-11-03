import SwiftUI

/// Mihon's library sheet: Filter, Sort and Display tabs.
struct LibrarySheet: View {
    enum Tab: String, CaseIterable, Identifiable {
        case filter = "Filter", sort = "Sort", display = "Display"
        var id: String { rawValue }
    }

    /// The category on screen (0 is Default); its sort is the one the Sort tab edits when categories sort separately.
    let shelfId: Int
    let shelfName: String
    @EnvironmentObject private var repo: LibraryRepository
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Pref.libraryFilters.name) private var storedFilters = ""
    @AppStorage(Pref.librarySort.name) private var storedSort = "title:asc"
    @AppStorage(Pref.perCategorySort.name) private var perCategory = false
    @AppStorage(Pref.libraryDefaultShelfSort.name) private var defaultShelfSort = ""
    @AppStorage(Pref.libraryDisplayMode.name) private var displayMode = "compact"
    @AppStorage(Pref.libraryColumnsPortrait.name) private var columnsPortrait = 0
    @AppStorage(Pref.libraryColumnsLandscape.name) private var columnsLandscape = 0
    @AppStorage(Pref.libraryBadgeUnread.name) private var badgeUnread = true
    @AppStorage(Pref.libraryBadgeDownloaded.name) private var badgeDownloaded = false
    @AppStorage(Pref.libraryBadgeLanguage.name) private var badgeLanguage = false
    @AppStorage(Pref.libraryBadgeLocal.name) private var badgeLocal = false
    @AppStorage(Pref.libraryShowCategoryTabs.name) private var showTabs = true
    @AppStorage(Pref.libraryShowItemCount.name) private var showCount = true
    @AppStorage(Pref.libraryContinueButton.name) private var continueButton = false
    @State private var tab = Tab.filter

    private var filters: Binding<LibraryFilters> {
        Binding(get: { LibraryFilters(stored: storedFilters) }, set: { storedFilters = $0.stored })
    }

    private var currentSort: LibrarySort {
        LibrarySort.effective(global: storedSort, perCategory: perCategory, shelfId: shelfId, defaultShelf: defaultShelfSort, categories: repo.categories)
    }

    var body: some View {
        NavigationStack {
            List {
                switch tab {
                case .filter: filterRows
                case .sort: sortRows
                case .display: displayRows
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Tab", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .themedScreen()
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Filter

    @ViewBuilder
    private var filterRows: some View {
        Section {
            triState("Downloaded", filters.downloaded)
            triState("Unread", filters.unread)
            triState("Started", filters.started)
            triState("Bookmarked", filters.bookmarked)
            triState("Completed", filters.completed)
            triState("Custom update interval", filters.customInterval)
        } footer: {
            Text("Tap once to show only matching titles, twice to hide them.")
        }
        .themedRows()
        if filters.wrappedValue.isActive {
            Section {
                Button("Clear filters", role: .destructive) { storedFilters = "" }
            }
            .themedRows()
        }
    }

    private func triState(_ title: String, _ state: Binding<LibraryTriState>) -> some View {
        Button {
            state.wrappedValue = state.wrappedValue.next
        } label: {
            HStack {
                Image(systemName: icon(state.wrappedValue))
                    .foregroundStyle(state.wrappedValue == .off ? Color.secondary : Color.accentColor)
                    .frame(width: 28)
                Text(title).foregroundStyle(.primary)
            }
        }
        .accessibilityValue(state.wrappedValue == .include ? "Included" : state.wrappedValue == .exclude ? "Excluded" : "Off")
    }

    private func icon(_ state: LibraryTriState) -> String {
        switch state {
        case .off: "square"
        case .include: "checkmark.square.fill"
        case .exclude: "minus.square.fill"
        }
    }

    // MARK: Sort

    @ViewBuilder
    private var sortRows: some View {
        let sort = currentSort
        Section {
            ForEach(LibrarySortKey.allCases) { key in
                Button {
                    save(sort.tapping(key))
                } label: {
                    HStack {
                        Image(systemName: sort.key == key && key != .random ? (sort.ascending ? "arrow.up" : "arrow.down") : "")
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 28)
                        Text(key.label).foregroundStyle(.primary)
                    }
                }
                .accessibilityAddTraits(sort.key == key ? .isSelected : [])
            }
        } header: {
            if perCategory { Text("Sort for \(shelfName)") }
        } footer: {
            Text("Tap the selected row again to reverse the order.")
        }
        .themedRows()
        Section {
            Toggle("Sort each category separately", isOn: $perCategory)
            if perCategory, hasOwnSort {
                Button("Use the library sort for \(shelfName)") { save(nil) }
            }
        }
        .themedRows()
    }

    private var hasOwnSort: Bool {
        shelfId == 0 ? !defaultShelfSort.isEmpty : repo.categories.first { Int($0.id) == shelfId }?.sortMode != nil
    }

    /// Per-category sorting saves to the shelf on screen; otherwise to the library-wide sort.
    private func save(_ sort: LibrarySort?) {
        guard perCategory else {
            if let sort { storedSort = sort.stored }
            return
        }
        if shelfId == 0 {
            defaultShelfSort = sort?.stored ?? ""
        } else {
            repo.setCategorySort(Int64(shelfId), sort)
        }
    }

    // MARK: Display

    @ViewBuilder
    private var displayRows: some View {
        Section("Display mode") {
            Picker("Display mode", selection: $displayMode) {
                ForEach(LibraryDisplayMode.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .themedRows()
        if displayMode != LibraryDisplayMode.list.rawValue {
            Section("Items per row") {
                columnsPicker("Portrait", $columnsPortrait)
                columnsPicker("Landscape", $columnsLandscape)
            }
            .themedRows()
        }
        Section("Badges") {
            Toggle("Unread chapters", isOn: $badgeUnread)
            Toggle("Downloaded chapters", isOn: $badgeDownloaded)
            Toggle("Language", isOn: $badgeLanguage)
            Toggle("Local source", isOn: $badgeLocal)
        }
        .themedRows()
        Section("Tabs") {
            Toggle("Show category tabs", isOn: $showTabs)
            Toggle("Show number of items", isOn: $showCount)
                .disabled(!showTabs)
        }
        .themedRows()
        Section {
            Toggle("Continue reading button", isOn: $continueButton)
        }
        .themedRows()
    }

    private func columnsPicker(_ title: String, _ selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            Text("Auto").tag(0)
            ForEach(2...10, id: \.self) { Text("\($0)").tag($0) }
        }
    }
}
