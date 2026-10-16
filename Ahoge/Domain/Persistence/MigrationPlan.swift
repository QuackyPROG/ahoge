import Foundation

struct MigrationOptions: Hashable {
    var reading = true
    var categories = true
    var tracking = true
    var history = true
    var notes = true
    var removeOriginal = false
}

struct MigrationPlan: Hashable {
    var original: Manga
    var target: Manga
    var targetChapters: [Chapter]
    var chapterMap: [String: String]
    var unmappedCount: Int

    static func build(original: Manga, target: Manga, originalChapters: [Chapter], targetChapters: [Chapter]) throws -> Self {
        guard original.id != target.id, original.sourceID != target.sourceID else { throw BackupError.invalid("Choose a different source edition.") }
        guard originalChapters.allSatisfy({ $0.mangaID == original.id && !$0.id.isEmpty }),
            targetChapters.allSatisfy({ $0.mangaID == target.id && !$0.id.isEmpty }),
            Set(originalChapters.map(\.id)).count == originalChapters.count,
            Set(targetChapters.map(\.id)).count == targetChapters.count else { throw BackupError.invalid("Invalid or duplicate chapter identities.") }
        let originalNumbers = Dictionary(grouping: originalChapters.filter { $0.number.isFinite && $0.number >= 0 }, by: \.number)
        let targetNumbers = Dictionary(grouping: targetChapters.filter { $0.number.isFinite && $0.number >= 0 }, by: \.number)
        var map: [String: String] = [:]
        for (number, chapters) in originalNumbers {
            if chapters.count == 1, let targets = targetNumbers[number], targets.count == 1 { map[chapters[0].id] = targets[0].id }
        }
        return Self(original: original, target: target, targetChapters: targetChapters, chapterMap: map,
            unmappedCount: originalChapters.count - map.count)
    }
}
