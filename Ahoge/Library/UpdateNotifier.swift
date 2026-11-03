import UserNotifications

/// Local notifications for library updates, and the app icon badge.
@MainActor
enum UpdateNotifier {
    static let thread = "app.ahoge.updates"

    private enum Key {
        static let kind = "kind"
        static let sourceId = "sourceId"
        static let url = "url"
        static let title = "title"
        static let cover = "cover"
    }

    /// Asks once; the system remembers the answer. Called when automatic updates are first turned on.
    static func requestAuthorization() {
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) }
    }

    private static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    /// "Ch. 120, Ch. 121"; a long run ends with "and N more".
    static func chapterList(_ chapters: [ChapterRecord], limit: Int = 3) -> String {
        let sorted = chapters.sorted { $0.number < $1.number }
        let shown = sorted.prefix(limit).map { $0.number >= 0 ? "Ch. " + String(format: "%g", $0.number) : $0.name }
        let rest = sorted.count - shown.count
        return shown.joined(separator: ", ") + (rest > 0 ? " and \(rest) more" : "")
    }

    /// One notification per title, grouped in one thread; a newer one for the same title replaces the older.
    static func notify(newChapters found: [(manga: LibraryManga, chapters: [ChapterRecord])], defaults: UserDefaults = .standard) async {
        guard !found.isEmpty, Pref.updateNotify.value(in: defaults) else { return }
        guard await isAuthorized() else { return }
        let hide = Pref.updateHideNotificationContent.value(in: defaults)
        for item in found {
            let content = UNMutableNotificationContent()
            if hide {
                content.title = "New chapters"
                content.body = item.chapters.count == 1 ? "1 new chapter" : "\(item.chapters.count) new chapters"
            } else {
                content.title = item.manga.title
                content.body = chapterList(item.chapters)
            }
            content.threadIdentifier = thread
            content.sound = .default
            content.userInfo = [
                Key.kind: "manga",
                Key.sourceId: item.manga.sourceId,
                Key.url: item.manga.url,
                Key.title: item.manga.title,
                Key.cover: item.manga.displayCover,
            ]
            let request = UNNotificationRequest(identifier: "update-" + item.manga.key, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    /// Tells that some titles failed; opening it shows the app, whose alert lists them.
    static func notifyFailures(count: Int) async {
        guard await isAuthorized() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Library update"
        content.body = count == 1 ? "1 title could not be updated" : "\(count) titles could not be updated"
        content.threadIdentifier = thread
        content.userInfo = [Key.kind: "failures"]
        let request = UNNotificationRequest(identifier: "update-failures", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Follows a tapped notification: a title opens its page, a failure report opens Updates.
    static func handleTap(_ info: [String: String], navigator: AppNavigator = .shared) {
        switch info[Key.kind] {
        case "manga":
            guard let sourceId = info[Key.sourceId], let url = info[Key.url] else { return }
            navigator.open(.manga(MangaRef(sourceId: sourceId, url: url, title: info[Key.title] ?? "", cover: info[Key.cover] ?? "")))
        case "failures":
            navigator.tab = .updates
        default:
            break
        }
    }

    /// The app icon badge: the Updates tab's unseen count.
    static func setBadge(_ count: Int) {
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(count) }
    }
}
