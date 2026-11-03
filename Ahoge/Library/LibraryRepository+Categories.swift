import Foundation
import GRDB
import SwiftUI

/// Values of `Pref.libraryDefaultCategory` besides a category id.
enum LibraryPrefs {
    static let alwaysAsk = -1
    static let uncategorized = 0
}

extension LibraryRepository {
    /// Adds a category at the end. Nil for a blank name or one already used (any case).
    @discardableResult
    func createCategory(named name: String) -> MangaCategory? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAvailableCategoryName(name) else { return nil }
        let sort = (categories.map(\.sort).max() ?? -1) + 1
        guard let id = try? db.write({ db -> Int64 in
            try db.execute(sql: "INSERT INTO category (name, sort) VALUES (?, ?)", arguments: [name, sort])
            return db.lastInsertedRowID
        }) else { return nil }
        let category = MangaCategory(id: id, name: name, sort: sort)
        objectWillChange.send()
        categories.append(category)
        return category
    }

    func isAvailableCategoryName(_ name: String, except id: Int64? = nil) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !categories.contains { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func renameCategory(_ id: Int64, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAvailableCategoryName(name, except: id), let index = categories.firstIndex(where: { $0.id == id }) else { return }
        objectWillChange.send()
        categories[index].name = name
        let category = categories[index]
        write { try category.update($0) }
    }

    /// Its titles stay in the library; those left in no category show under Default.
    func deleteCategory(_ id: Int64) {
        if UserDefaults.standard.object(forKey: Pref.libraryDefaultCategory.name) as? Int == Int(id) {
            UserDefaults.standard.set(LibraryPrefs.alwaysAsk, forKey: Pref.libraryDefaultCategory.name)
        }
        objectWillChange.send()
        categories.removeAll { $0.id == id }
        for key in Array(categoryLinks.keys) {
            categoryLinks[key]?.remove(id)
            if categoryLinks[key]?.isEmpty == true { categoryLinks[key] = nil }
        }
        write { try $0.execute(sql: "DELETE FROM category WHERE id = ?", arguments: [id]) }
    }

    func moveCategories(fromOffsets source: IndexSet, toOffset destination: Int) {
        objectWillChange.send()
        categories.move(fromOffsets: source, toOffset: destination)
        for index in categories.indices { categories[index].sort = index }
        let ordered = categories
        write { db in
            for category in ordered { try category.update(db) }
        }
    }

    /// Sets or clears a `flags` mask of a category (1: skip in updates, 2: skip auto-download).
    func setCategoryFlag(_ id: Int64, mask: Int, on: Bool) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        objectWillChange.send()
        if on { categories[index].flags |= mask } else { categories[index].flags &= ~mask }
        let category = categories[index]
        write { try category.update($0) }
    }

    func categoryIds(of manga: LibraryManga) -> Set<Int64> { categoryLinks[manga.key] ?? [] }

    func setCategories(_ ids: Set<Int64>, for manga: LibraryManga) {
        // A deleted category's id would fail the foreign key and roll back the whole write.
        let ids = ids.filter { id in categories.contains { $0.id == id } }
        objectWillChange.send()
        categoryLinks[manga.key] = ids.isEmpty ? nil : ids
        write { db in
            try db.execute(sql: "DELETE FROM mangaCategory WHERE mangaKey = ?", arguments: [manga.key])
            for id in ids {
                try db.execute(sql: "INSERT INTO mangaCategory (mangaKey, categoryId) VALUES (?, ?)", arguments: [manga.key, id])
            }
        }
    }

    /// Library titles on one shelf; nil is Default (titles in no category).
    func library(in categoryId: Int64?) -> [LibraryManga] {
        guard let categoryId else { return library.filter { categoryLinks[$0.key] == nil } }
        return library.filter { categoryLinks[$0.key]?.contains(categoryId) == true }
    }

    /// Saves `manga` to the library in the default category (an id, `uncategorized` or
    /// `alwaysAsk`). True when the user should pick categories now.
    @discardableResult
    func addToLibrary(_ manga: LibraryManga, defaultCategory: Int) -> Bool {
        setInLibrary(manga, true)
        if defaultCategory > 0 {
            guard categories.contains(where: { $0.id == Int64(defaultCategory) }) else { return !categories.isEmpty }
            setCategories([Int64(defaultCategory)], for: manga)
            return false
        }
        return defaultCategory == LibraryPrefs.alwaysAsk && !categories.isEmpty
    }
}
