import Foundation

struct ReaderProgressSelection {
    let focusedIndex: Int
    let totalPages: Int
    let focusedSourceID: String
    let finalSourceVisible: Bool
    let chapterID: String
}

struct ReaderProgressDecision {
    let pageIndex: Int
    let totalPages: Int
    let isRead: Bool
    let writesHistory: Bool
}

enum ReaderProgressPolicy {
    static func selection(snapshot: ReaderContentSnapshot?, chapterID: String, focusedIndex: Int,
                          visibleGroup: ReaderDisplayGroup?, visibilityCommitted: Bool) -> ReaderProgressSelection? {
        guard let snapshot, snapshot.chapterID == chapterID,
              snapshot.renderData.logicalPages.indices.contains(focusedIndex) else { return nil }
        let focused = snapshot.renderData.logicalPages[focusedIndex]
        let committedGroup = visibleGroup.flatMap { candidate in
            snapshot.displayGroups.first { $0.id == candidate.id }
        }
        let visibleFinal = visibilityCommitted && committedGroup.map { group in
            group.members.count == 2 && group.contains(focusedIndex) &&
            group.members.allSatisfy { member in
                if case .full = member.fragment { return snapshot.renderData.renderItems.contains { $0.id == member.id } }
                return false
            } && group.reachesEnd(sourceCount: snapshot.pages.count)
        } == true
        return ReaderProgressSelection(focusedIndex: focusedIndex, totalPages: snapshot.renderData.logicalPages.count,
            focusedSourceID: focused.sourcePage.id, finalSourceVisible: visibleFinal, chapterID: chapterID)
    }

    static func decision(pageIndex: Int, totalPages: Int, previousChapterMatches: Bool,
                         previousTotal: Int, wasRead: Bool, incognito: Bool,
                         finalSourceVisible: Bool) -> ReaderProgressDecision {
        let total = max(0, totalPages, previousChapterMatches ? previousTotal : 0)
        let bounded = min(max(pageIndex, 0), max(total - 1, 0))
        return ReaderProgressDecision(pageIndex: bounded, totalPages: total,
            isRead: wasRead || (total > 0 && (bounded == total - 1 || finalSourceVisible)),
            writesHistory: !incognito)
    }
}
