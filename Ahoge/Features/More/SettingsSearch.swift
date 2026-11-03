import SwiftUI

/// Where a settings row lives, so a search result can open its screen. nil is a row on More itself
/// or inside the reader's own settings sheet.
enum SettingsDestination: Hashable {
    case appearance, categories, libraryUpdates, migrate, downloadQueue, downloadSettings, dataStorage, clearDatabase, advanced
    case statistics, whatsNew, licenses

    @ViewBuilder var screen: some View {
        switch self {
        case .appearance: AppearanceView()
        case .categories: CategoriesView()
        case .libraryUpdates: UpdateSettingsView()
        case .migrate: MigrateSourcesView()
        case .downloadQueue: DownloadQueueView()
        case .downloadSettings: DownloadSettingsView()
        case .dataStorage: DataStorageView()
        case .clearDatabase: ClearDatabaseView()
        case .advanced: AdvancedView()
        case .statistics: StatisticsView()
        case .whatsNew: WhatsNewView()
        case .licenses: LicensesView()
        }
    }
}

struct SettingsEntry: Identifiable {
    let title: String
    /// The screen's name, shown under the title.
    let place: String
    let destination: SettingsDestination?
    /// Other words that should find it.
    var keywords: [String] = []
    var id: String { place + "\n" + title }
}

/// Every settings row by its title, for More's search field.
enum SettingsIndex {
    static let entries: [SettingsEntry] = [
        // More
        SettingsEntry(title: "Downloaded only", place: "More", destination: nil, keywords: ["offline"]),
        SettingsEntry(title: "Extension repositories", place: "More", destination: nil, keywords: ["sources", "index", "add"]),
        SettingsEntry(title: "Default category", place: "More", destination: nil),
        SettingsEntry(title: "Swipe right", place: "More", destination: nil, keywords: ["chapter", "gesture"]),
        SettingsEntry(title: "Swipe left", place: "More", destination: nil, keywords: ["chapter", "gesture"]),
        SettingsEntry(title: "Hide missing chapter count", place: "More", destination: nil),
        SettingsEntry(title: "Mark duplicate chapters read", place: "More", destination: nil),
        SettingsEntry(title: "Hide titles in your library", place: "More", destination: nil, keywords: ["browse"]),
        SettingsEntry(title: "Incognito mode", place: "More", destination: nil, keywords: ["privacy", "history"]),
        SettingsEntry(title: "Hide content in app switcher", place: "More", destination: nil, keywords: ["privacy", "blur", "secure"]),
        SettingsEntry(title: "Require unlock", place: "More", destination: nil, keywords: ["app lock", "face id", "touch id", "passcode", "biometric"]),
        SettingsEntry(title: "Welcome guide", place: "More", destination: nil, keywords: ["onboarding", "help"]),
        SettingsEntry(title: "Check for updates", place: "More", destination: nil, keywords: ["release", "version", "about"]),
        // Screens
        SettingsEntry(title: "Statistics", place: "More", destination: .statistics, keywords: ["time read", "chapters", "library size"]),
        SettingsEntry(title: "What's new", place: "More", destination: .whatsNew, keywords: ["release notes", "changelog"]),
        SettingsEntry(title: "Licenses", place: "More", destination: .licenses, keywords: ["open source"]),
        SettingsEntry(title: "Categories", place: "Library", destination: .categories, keywords: ["tabs", "folders", "shelves"]),
        SettingsEntry(title: "Migrate", place: "Library", destination: .migrate, keywords: ["move", "switch source"]),
        // Appearance
        SettingsEntry(title: "Theme mode", place: "Appearance", destination: .appearance, keywords: ["dark", "light", "system"]),
        SettingsEntry(title: "App theme", place: "Appearance", destination: .appearance, keywords: ["colour", "color"]),
        SettingsEntry(title: "Pure black dark mode", place: "Appearance", destination: .appearance, keywords: ["amoled", "oled"]),
        SettingsEntry(title: "Date format", place: "Appearance", destination: .appearance),
        SettingsEntry(title: "Relative timestamps", place: "Appearance", destination: .appearance, keywords: ["today", "yesterday"]),
        // Library updates
        SettingsEntry(title: "Automatic updates", place: "Library updates", destination: .libraryUpdates, keywords: ["interval", "background", "refresh"]),
        SettingsEntry(title: "Only while charging", place: "Library updates", destination: .libraryUpdates, keywords: ["power", "battery"]),
        SettingsEntry(title: "Skip titles", place: "Library updates", destination: .libraryUpdates, keywords: ["unread", "not started", "completed"]),
        SettingsEntry(title: "Smart update", place: "Library updates", destination: .libraryUpdates, keywords: ["predict", "schedule"]),
        SettingsEntry(title: "Refresh metadata", place: "Library updates", destination: .libraryUpdates, keywords: ["details", "cover"]),
        SettingsEntry(title: "Update titles to match source", place: "Library updates", destination: .libraryUpdates, keywords: ["rename"]),
        SettingsEntry(title: "Notify about new chapters", place: "Library updates", destination: .libraryUpdates, keywords: ["notifications"]),
        SettingsEntry(title: "Hide notification content", place: "Library updates", destination: .libraryUpdates, keywords: ["privacy"]),
        SettingsEntry(title: "Unseen updates badge", place: "Library updates", destination: .libraryUpdates, keywords: ["app icon"]),
        // Downloads
        SettingsEntry(title: "Download queue", place: "Downloads", destination: .downloadQueue, keywords: ["pause", "resume"]),
        SettingsEntry(title: "Only on Wi-Fi", place: "Download settings", destination: .downloadSettings, keywords: ["cellular", "mobile data"]),
        SettingsEntry(title: "Sources at once", place: "Download settings", destination: .downloadSettings, keywords: ["concurrent", "parallel"]),
        SettingsEntry(title: "Pages at once", place: "Download settings", destination: .downloadSettings, keywords: ["concurrent", "parallel"]),
        SettingsEntry(title: "Save as CBZ archive", place: "Download settings", destination: .downloadSettings, keywords: ["zip"]),
        SettingsEntry(title: "After reading", place: "Download settings", destination: .downloadSettings, keywords: ["delete", "remove downloads"]),
        SettingsEntry(title: "After manually marked as read", place: "Download settings", destination: .downloadSettings, keywords: ["delete", "remove downloads"]),
        SettingsEntry(title: "Delete bookmarked chapters", place: "Download settings", destination: .downloadSettings),
        SettingsEntry(title: "Download new chapters", place: "Download settings", destination: .downloadSettings, keywords: ["automatic"]),
        SettingsEntry(title: "Download ahead", place: "Download settings", destination: .downloadSettings, keywords: ["next chapters"]),
        // Data and storage
        SettingsEntry(title: "Create backup", place: "Data and storage", destination: .dataStorage, keywords: ["export", "save"]),
        SettingsEntry(title: "Restore backup", place: "Data and storage", destination: .dataStorage, keywords: ["import", "mihon", "tachiyomi"]),
        SettingsEntry(title: "Automatic backup", place: "Data and storage", destination: .dataStorage, keywords: ["schedule", "backups to keep"]),
        SettingsEntry(title: "Clear database", place: "Data and storage", destination: .clearDatabase, keywords: ["remove", "non-library"]),
        SettingsEntry(title: "Export library list (CSV)", place: "Data and storage", destination: .dataStorage, keywords: ["spreadsheet"]),
        SettingsEntry(title: "Reset per-series reader settings", place: "Data and storage", destination: .dataStorage),
        SettingsEntry(title: "Clear image cache", place: "Data and storage", destination: .dataStorage, keywords: ["storage", "space"]),
        SettingsEntry(title: "Clear chapter cache", place: "Data and storage", destination: .dataStorage, keywords: ["storage", "space"]),
        SettingsEntry(title: "Clear chapter cache on launch", place: "Data and storage", destination: .dataStorage),
        SettingsEntry(title: "Reindex downloads", place: "Data and storage", destination: .dataStorage),
        SettingsEntry(title: "Clear cookies and website data", place: "Data and storage", destination: .dataStorage, keywords: ["cloudflare", "login"]),
        // Advanced
        SettingsEntry(title: "User agent", place: "Advanced", destination: .advanced, keywords: ["custom", "browser"]),
        SettingsEntry(title: "Share logs", place: "Advanced", destination: .advanced, keywords: ["debug", "diagnostics", "bug"]),
        // Reader (its own sheet)
        SettingsEntry(title: "Reading mode", place: "Reader settings", destination: nil, keywords: ["webtoon", "paged", "right to left", "vertical"]),
        SettingsEntry(title: "Rotation", place: "Reader settings", destination: nil, keywords: ["orientation", "lock"]),
        SettingsEntry(title: "Background", place: "Reader settings", destination: nil, keywords: ["black", "white", "gray"]),
        SettingsEntry(title: "Tap zones", place: "Reader settings", destination: nil, keywords: ["navigation", "invert"]),
        SettingsEntry(title: "Scale type", place: "Reader settings", destination: nil, keywords: ["fit", "zoom"]),
        SettingsEntry(title: "Crop borders", place: "Reader settings", destination: nil, keywords: ["margins"]),
        SettingsEntry(title: "Wide pages", place: "Reader settings", destination: nil, keywords: ["split", "spread"]),
        SettingsEntry(title: "Dual page view", place: "Reader settings", destination: nil, keywords: ["two pages", "landscape"]),
        SettingsEntry(title: "Colour filter", place: "Reader settings", destination: nil, keywords: ["brightness", "dim", "night", "grayscale", "invert"]),
        SettingsEntry(title: "Keep screen on", place: "Reader settings", destination: nil),
        SettingsEntry(title: "Show page number", place: "Reader settings", destination: nil),
        SettingsEntry(title: "Skip read chapters", place: "Reader settings", destination: nil, keywords: ["next chapter", "duplicates", "filtered"]),
        SettingsEntry(title: "Preload only on Wi-Fi", place: "Reader settings", destination: nil),
    ]

    /// Entries that contain every word of `query` in their title, place or keywords (case and accents ignored).
    static func search(_ query: String, in entries: [SettingsEntry] = entries) -> [SettingsEntry] {
        let words = query.split(whereSeparator: \.isWhitespace).map { normalized(String($0)) }
        guard !words.isEmpty else { return [] }
        return entries.filter { entry in
            let haystack = normalized(([entry.title, entry.place] + entry.keywords).joined(separator: " "))
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// Results laid over More while its search field has text.
struct SettingsSearchResults: View {
    let query: String

    var body: some View {
        let results = SettingsIndex.search(query)
        List {
            if results.isEmpty {
                Text("No settings match \"\(query)\".").foregroundStyle(.secondary).themedRows()
            }
            ForEach(results) { entry in
                if let destination = entry.destination {
                    NavigationLink { destination.screen } label: { row(entry) }
                } else {
                    row(entry)
                }
            }
            .themedRows()
        }
        .themedScreen()
    }

    private func row(_ entry: SettingsEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.title)
            Text(entry.destination == nil && entry.place == "Reader settings" ? "Reader settings (open a chapter)" : entry.place)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
