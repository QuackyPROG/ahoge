// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

//
//  LibraryDomain.swift
//  Ahoge
//

import Foundation

struct Category: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    let systemImage: String
}

struct LibraryEntry: Identifiable, Codable, Hashable {
    var id: String { mangaID }
    let mangaID: String
    var categoryID: String
    let addedAt: Date
    var categoryIDs: Set<String>

    init(mangaID: String, categoryID: String, addedAt: Date, categoryIDs: Set<String>? = nil) {
        self.mangaID = mangaID
        self.categoryIDs = categoryIDs.flatMap { $0.isEmpty ? nil : $0 } ?? [categoryID]
        self.categoryID = self.categoryIDs.contains(categoryID) ? categoryID : self.categoryIDs.sorted().first ?? ""
        self.addedAt = addedAt
    }

    enum CodingKeys: String, CodingKey { case mangaID, categoryID, categoryIDs, addedAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(mangaID: try c.decode(String.self, forKey: .mangaID),
                  categoryID: try c.decodeIfPresent(String.self, forKey: .categoryID) ?? "",
                  addedAt: try c.decode(Date.self, forKey: .addedAt),
                  categoryIDs: try c.decodeIfPresent(Set<String>.self, forKey: .categoryIDs))
    }
}

struct ChapterState: Codable, Hashable {
    var mangaID: String
    var chapterID: String
    var isRead: Bool = false
    var isBookmarked: Bool = false
    var pageIndex: Int = 0
    var totalPages: Int = 0
}

struct ReadingProgress: Identifiable, Codable, Hashable {
    var id: String { mangaID }
    let mangaID: String
    var chapterID: String
    var chapterTitle: String?
    var pageIndex: Int
    var totalPages: Int
    var updatedAt: Date
}

struct HistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let mangaID: String
    let chapterID: String
    let pageIndex: Int
    let timestamp: Date
}

struct UpdateEntry: Identifiable, Hashable {
    let id: String
    let mangaID: String
    let chapterID: String
    let sourceID: String
    let isBookmarked: Bool
}

struct LibraryManga: Identifiable, Hashable {
    let id: String
    let manga: Manga
    let entry: LibraryEntry
    let progress: ReadingProgress?
    let latestChapter: Chapter?
}

struct UpdateFeedItem: Identifiable, Hashable {
    let id: String
    let manga: Manga
    let chapter: Chapter
    let entry: UpdateEntry
}
