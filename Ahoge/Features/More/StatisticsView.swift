import SwiftUI

/// Mihon's Statistics: the library in numbers.
struct StatisticsView: View {
    @EnvironmentObject private var repo: LibraryRepository
    @EnvironmentObject private var downloads: DownloadManager

    var body: some View {
        let library = repo.library
        let seconds = repo.historyByChapter().mapValues(\.timeRead)
        let counts = Dictionary(uniqueKeysWithValues: library.map { ($0.key, downloads.downloadedCount(mangaKey: $0.key)) })
        let stats = LibraryStatistics.compute(manga: library, history: seconds, downloaded: counts)
        List {
            Section("Library") {
                row("Titles", stats.titles, "books.vertical.fill", .blue)
                row("Completed", stats.completed, "checkmark.seal.fill", .green)
                row("Started reading", stats.started, "book.fill", .orange)
                row("Local titles", stats.local, "folder.fill", .brown)
                row("Sources", stats.sources, "safari.fill", .indigo)
            }
            .themedRows()
            Section("Chapters") {
                row("Total", stats.chaptersTotal, "list.number", .gray)
                row("Read", stats.chaptersRead, "eye.fill", .teal)
                row("Downloaded", stats.chaptersDownloaded, "arrow.down.circle.fill", .blue)
            }
            .themedRows()
            Section {
                LabeledContent {
                    Text(LibraryStatistics.duration(stats.readSeconds))
                } label: {
                    Label { Text("Time read") } icon: { SettingsIcon(systemName: "clock.fill", color: .purple) }
                }
            } footer: {
                Text("Counted while a chapter is open in the reader. Incognito reading is not counted.")
            }
            .themedRows()
        }
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
        .themedScreen()
    }

    private func row(_ title: String, _ value: Int, _ symbol: String, _ color: Color) -> some View {
        LabeledContent {
            Text("\(value)")
        } label: {
            Label { Text(title) } icon: { SettingsIcon(systemName: symbol, color: color) }
        }
    }
}
