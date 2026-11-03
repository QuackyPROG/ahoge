import SwiftUI

/// What a swipe on a chapter row can do (Mihon's configurable swipe actions).
enum ChapterSwipeAction: String, CaseIterable, Identifiable {
    case none, bookmark, read, download
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .bookmark: "Bookmark"
        case .read: "Mark as read"
        case .download: "Download"
        }
    }
}

/// Adds the two swipes chosen in More > Chapters to a chapter row.
private struct ChapterSwipes: ViewModifier {
    @ObservedObject var chapter: ChapterRecord
    @EnvironmentObject private var repo: LibraryRepository
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.palette) private var palette
    @AppStorage(Pref.swipeRight.name) private var right = Pref.swipeRight.defaultValue
    @AppStorage(Pref.swipeLeft.name) private var left = Pref.swipeLeft.defaultValue

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading) { button(ChapterSwipeAction(rawValue: right) ?? .none) }
            .swipeActions(edge: .trailing) { button(ChapterSwipeAction(rawValue: left) ?? .none) }
    }

    @ViewBuilder
    private func button(_ action: ChapterSwipeAction) -> some View {
        switch action {
        case .none:
            EmptyView()
        case .read:
            Button(chapter.read ? "Unread" : "Read", systemImage: chapter.read ? "eye.slash" : "eye") { repo.setRead([chapter], !chapter.read) }
                .tint(Color(uiColor: UIColor(rgb: palette.primary.light))) // UIKit draws swipe labels white
        case .bookmark:
            Button(chapter.bookmark ? "Unbookmark" : "Bookmark", systemImage: chapter.bookmark ? "bookmark.slash" : "bookmark") {
                repo.setBookmark([chapter], !chapter.bookmark)
            }
            .tint(.orange)
        case .download:
            if downloads.isDownloaded(chapter.key) {
                Button("Delete", systemImage: "trash") { downloads.delete([chapter]) }.tint(.red)
            } else {
                Button("Download", systemImage: "arrow.down.circle") { downloads.enqueue([chapter]) }
                    .tint(Color(uiColor: UIColor(rgb: palette.primary.light)))
            }
        }
    }
}

extension View {
    func chapterSwipes(_ chapter: ChapterRecord) -> some View { modifier(ChapterSwipes(chapter: chapter)) }
}
