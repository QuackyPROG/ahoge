import SwiftUI

/// When the next library update will check each title, by day (smart update's predictions and
/// custom intervals).
struct UpcomingView: View {
    @EnvironmentObject private var repo: LibraryRepository
    @EnvironmentObject private var sources: SourceManager

    private struct Entry: Identifiable {
        let manga: LibraryManga
        let date: Date
        var id: String { manga.key }
    }

    private struct Day: Identifiable {
        let day: Date
        let entries: [Entry]
        var id: Date { day }
    }

    private func days() -> [Day] {
        let rules = UpdateRules.current(categories: repo.categories)
        let now = Date()
        let calendar = Calendar.current
        let entries = repo.library.compactMap { manga -> Entry? in
            let reason = UpdatePolicy.decide(manga, categories: repo.categoryIds(of: manga), rules: rules, now: now)
            guard reason == nil || reason == .notDue, let due = UpdatePolicy.dueDate(manga, rules: rules) else { return nil }
            // Already overdue: it goes with the next update, which can start any time.
            return Entry(manga: manga, date: max(due, now))
        }
        return Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
            .map { Day(day: $0.key, entries: $0.value.sorted { ($0.date, $0.manga.title) < ($1.date, $1.manga.title) }) }
            .sorted { $0.day < $1.day }
    }

    private func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    var body: some View {
        let groups = days()
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.entries) { entry in
                        NavigationLink(value: Route.manga(entry.manga.ref)) {
                            HStack(spacing: 12) {
                                RemoteImage(url: entry.manga.displayCover, headers: referer(entry.manga), maxPixelWidth: 150)
                                    .frame(width: 44, height: 62)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.manga.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    Text(sources.installed(entry.manga.sourceId)?.name ?? entry.manga.sourceId)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text(title(for: group.day))
                }
                .themedRows(plain: true)
            }
        }
        .listStyle(.plain)
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("Nothing scheduled", systemImage: "calendar", description: Text("Titles show up here once smart update has predicted when they release, or when they have their own interval."))
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle("Upcoming")
        .navigationBarTitleDisplayMode(.inline)
        .themedScreen()
    }

    private func referer(_ manga: LibraryManga) -> [String: String] {
        sources.installed(manga.sourceId).map { ["Referer": $0.baseUrl + "/"] } ?? [:]
    }
}
