import Foundation

extension AppModel {
    var unreadUpdatesCount: Int { updateFeed.filter { !isUpdateSeen($0) }.count }

    func isUpdateSeen(_ item: UpdateFeedItem) -> Bool {
        state.updatesSeenChapterIDs.contains(item.chapter.id) ||
            state.updatesLastSeenChapterIDByMangaID[item.manga.id] == item.chapter.id
    }

    func markUpdatesSeen(_ items: [UpdateFeedItem]) {
        let ids = Set(items.map { $0.chapter.id })
        guard !ids.isSubset(of: state.updatesSeenChapterIDs) else { return }
        state.updatesSeenChapterIDs.formUnion(ids)
        persist()
    }

    func markAllUpdatesSeen() { markUpdatesSeen(updateFeed) }
}
