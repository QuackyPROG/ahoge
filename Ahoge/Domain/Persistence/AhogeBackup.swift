import Foundation

enum BackupSection: String, Codable, CaseIterable, Identifiable {
    case library, history, tracking, preferences, sources, notes
    var id: String { rawValue }
}

struct BackupCollection: Codable, Hashable {
    var categories: [Category]
    var entries: [LibraryEntry]
    var mangas: [Manga]
    var chapters: [String: [Chapter]]
    var progress: [ReadingProgress]
    var chapterStates: [String: ChapterState]
    var seen: Set<String>
}

struct BackupPreferences: Codable, Hashable {
    var reader: ReaderPreferences
    var library: LibraryPreferences
    var app: AppSettings
    var downloads: DownloadPreferences
    var browse: BrowsePreferences
    var advanced: AdvancedPreferences
}

struct AhogeBackup: Codable, Hashable {
    static let version = 1
    static let maximumBytes = 32 * 1_024 * 1_024
    var schemaVersion: Int = version
    var createdAt: Date
    var appVersion: String
    var sections: Set<BackupSection>
    var collection: BackupCollection?
    var history: [HistoryEntry]?
    var trackers: [TrackerBinding]?
    var preferences: BackupPreferences?
    var repositories: [SourceRepoRecord]?
    var notes: [String: String]?
    var supportingMangas: [Manga]?
    var supportingChapters: [String: [Chapter]]?

    func validate() throws {
        guard schemaVersion == Self.version, !sections.isEmpty else { throw BackupError.invalid("Unsupported backup version or empty selection.") }
        guard (collection != nil) == sections.contains(.library), (history != nil) == sections.contains(.history),
            (trackers != nil) == sections.contains(.tracking), (preferences != nil) == sections.contains(.preferences),
            (repositories != nil) == sections.contains(.sources), (notes != nil) == sections.contains(.notes)
            else { throw BackupError.invalid("Backup section contents do not match its selection.") }
        func unique(_ ids: [String]) throws {
            guard ids.allSatisfy({ !$0.isEmpty }), Set(ids).count == ids.count else { throw BackupError.invalid("Empty or duplicate identities.") }
        }
        guard (supportingMangas == nil) == (supportingChapters == nil), collection == nil || supportingMangas == nil else { throw BackupError.invalid("Conflicting backup metadata.") }
        let needsReferences = !(history ?? []).isEmpty || !(trackers ?? []).isEmpty || !(notes ?? [:]).isEmpty
        guard !needsReferences || collection != nil || supportingMangas != nil else { throw BackupError.invalid("Selected records need supporting title and chapter metadata.") }
        let support = supportingMangas.map { BackupCollection(categories: [], entries: [], mangas: $0,
            chapters: supportingChapters ?? [:], progress: [], chapterStates: [:], seen: []) }
        if let c = collection ?? support {
            try unique(c.mangas.map(\.id)); try unique(c.entries.map(\.mangaID)); try unique(c.categories.map(\.id))
            let mangaIDs = Set(c.mangas.map(\.id)), categories = Set(c.categories.map(\.id)).union([""])
            guard c.entries.allSatisfy({ mangaIDs.contains($0.mangaID) && $0.categoryIDs.isSubset(of: categories) }) else { throw BackupError.invalid("Invalid library or category references.") }
            var chapterIDs = Set<String>()
            var owners: [String: String] = [:]
            for (mangaID, chapters) in c.chapters {
                guard mangaIDs.contains(mangaID) else { throw BackupError.invalid("Unknown chapter owner.") }
                for chapter in chapters {
                    guard chapter.mangaID == mangaID, !chapter.id.isEmpty, chapterIDs.insert(chapter.id).inserted,
                        !chapter.isDownloaded, chapter.pages.allSatisfy({ $0.assetPath == nil }) else { throw BackupError.invalid("Invalid chapter identity or portable file metadata.") }
                    owners[chapter.id] = mangaID
                }
            }
            try unique(c.progress.map(\.mangaID))
            guard c.progress.allSatisfy({ mangaIDs.contains($0.mangaID) && owners[$0.chapterID] == $0.mangaID && $0.pageIndex >= 0 && $0.totalPages >= 0 }),
                c.chapterStates.allSatisfy({ $0.key == $0.value.chapterID && mangaIDs.contains($0.value.mangaID) && owners[$0.value.chapterID] == $0.value.mangaID && $0.value.pageIndex >= 0 })
                else { throw BackupError.invalid("Invalid progress references.") }
            if let history { guard history.allSatisfy({ mangaIDs.contains($0.mangaID) && owners[$0.chapterID] == $0.mangaID }) else { throw BackupError.invalid("History references missing chapter metadata.") } }
            if let trackers { guard trackers.allSatisfy({ mangaIDs.contains($0.mangaID) }) else { throw BackupError.invalid("Tracker references missing title metadata.") } }
            if let notes { guard Set(notes.keys).isSubset(of: mangaIDs) else { throw BackupError.invalid("Notes reference missing title metadata.") } }
        }
        if let history { try unique(history.map { $0.id.uuidString }); guard history.allSatisfy({ !$0.mangaID.isEmpty && !$0.chapterID.isEmpty && $0.pageIndex >= 0 }) else { throw BackupError.invalid("Invalid history.") } }
        if let trackers {
            try unique(trackers.map { $0.id.uuidString })
            let keys = trackers.map { $0.mangaID + "::" + $0.service.rawValue }
            guard Set(keys).count == keys.count, trackers.allSatisfy({ !$0.mangaID.isEmpty }) else { throw BackupError.invalid("Duplicate local tracker bindings or missing title identity.") }
        }
        if let repositories { try unique(repositories.map(\.id)); guard repositories.allSatisfy({ URL(string: $0.url)?.scheme == "https" }) else { throw BackupError.invalid("Invalid repository URL.") } }
    }

    static func decode(_ data: Data) throws -> AhogeBackup {
        guard data.count <= maximumBytes else { throw BackupError.invalid("Backup exceeds 32 MB.") }
        try BackupJSONValidation.validate(data)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(Self.self, from: data)
        try backup.validate()
        return backup
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw BackupError.invalid("Backup exceeds 32 MB.") }
        return data
    }
}

enum BackupError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let reason): return reason } }
}
