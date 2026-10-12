// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

//
//  BackupMigrationDomain.swift
//  Ahoge
//

import Foundation

struct BackupPayload: Identifiable, Hashable {
    let id: UUID
    let createdAt: Date
    let sections: [String]
    let itemCount: Int
}

struct MigrationCandidate: Identifiable, Hashable {
    let id: String
    let source: Source
    let manga: Manga
}

