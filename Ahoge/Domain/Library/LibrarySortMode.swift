// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

//
//  LibrarySortMode.swift
//  Ahoge
//

import Foundation

enum LibrarySortMode: String, Codable, CaseIterable, Identifiable {
    case recent
    case alphabetical
    case added, lastRead, lastUpdate, unreadCount, latestChapter, random
    case chapterCount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .added: return "Date added"
        case .lastRead: return "Last read"
        case .lastUpdate: return "Last chapter update"
        case .unreadCount: return "Unread chapters"
        case .latestChapter: return "Latest chapter number"
        case .random: return "Random"
        case .recent: return "Recent"
        case .alphabetical: return "A-Z"
        case .chapterCount: return "Chapters"
        }
    }
}

