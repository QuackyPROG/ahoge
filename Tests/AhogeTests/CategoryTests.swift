import XCTest
@testable import Ahoge

@MainActor
final class CategoryTests: XCTestCase {
    private func libraryWithTwo() throws -> (LibraryRepository, LibraryManga, LibraryManga) {
        let repo = try LibraryRepository.inMemory()
        let a = repo.upsert(sourceId: "en.demo", url: "/m/a", title: "A", cover: "")
        let b = repo.upsert(sourceId: "en.demo", url: "/m/b", title: "B", cover: "")
        repo.setInLibrary(a, true)
        repo.setInLibrary(b, true)
        return (repo, a, b)
    }

    func testCreateRejectsBlankAndDuplicateNames() throws {
        let repo = try LibraryRepository.inMemory()
        XCTAssertNotNil(repo.createCategory(named: " Reading "))
        XCTAssertEqual(repo.categories.map(\.name), ["Reading"])
        XCTAssertNil(repo.createCategory(named: "reading"))
        XCTAssertNil(repo.createCategory(named: "   "))
    }

    func testShelvesSplitTheLibrary() throws {
        let (repo, a, b) = try libraryWithTwo()
        let reading = try XCTUnwrap(repo.createCategory(named: "Reading"))
        repo.setCategories([reading.id], for: a)
        XCTAssertEqual(repo.library(in: reading.id).map(\.key), [a.key])
        XCTAssertEqual(repo.library(in: nil).map(\.key), [b.key])
    }

    func testRenameReorderDelete() throws {
        let key = Pref.libraryDefaultCategory.name
        let saved = UserDefaults.standard.object(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        let (repo, a, _) = try libraryWithTwo()
        let one = try XCTUnwrap(repo.createCategory(named: "One"))
        let two = try XCTUnwrap(repo.createCategory(named: "Two"))
        repo.renameCategory(one.id, to: "two")
        XCTAssertEqual(repo.categories.map(\.name), ["One", "Two"])
        repo.renameCategory(one.id, to: "First")
        repo.moveCategories(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        XCTAssertEqual(repo.categories.map(\.name), ["Two", "First"])
        XCTAssertEqual(repo.categories.map(\.sort), [0, 1])
        repo.setCategories([two.id], for: a)
        repo.deleteCategory(two.id)
        XCTAssertEqual(repo.categoryIds(of: a), [])
        XCTAssertEqual(repo.library(in: nil).count, 2)
    }

    func testCategoriesSurviveReopen() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("library-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: file) }
        let repo = try LibraryRepository.open(at: file)
        let manga = repo.upsert(sourceId: "en.demo", url: "/m/1", title: "One", cover: "")
        repo.setInLibrary(manga, true)
        let first = try XCTUnwrap(repo.createCategory(named: "First"))
        let second = try XCTUnwrap(repo.createCategory(named: "Second"))
        repo.moveCategories(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        repo.setCategories([first.id, second.id], for: manga)

        let reopened = try LibraryRepository.open(at: file)
        XCTAssertEqual(reopened.categories.map(\.name), ["Second", "First"])
        let loaded = try XCTUnwrap(reopened.manga(key: manga.key))
        XCTAssertEqual(reopened.categoryIds(of: loaded), [first.id, second.id])
    }

    func testRemovingFromLibraryClearsCategories() throws {
        let (repo, a, _) = try libraryWithTwo()
        let reading = try XCTUnwrap(repo.createCategory(named: "Reading"))
        repo.setCategories([reading.id], for: a)
        repo.setInLibrary(a, false)
        XCTAssertEqual(repo.categoryIds(of: a), [])
    }

    func testAddToLibraryUsesTheDefaultCategory() throws {
        let repo = try LibraryRepository.inMemory()
        let manga = repo.upsert(sourceId: "en.demo", url: "/m/1", title: "One", cover: "")
        // No categories yet: nothing to ask.
        XCTAssertFalse(repo.addToLibrary(manga, defaultCategory: LibraryPrefs.alwaysAsk))
        XCTAssertTrue(manga.inLibrary)
        repo.setInLibrary(manga, false)
        let favorite = try XCTUnwrap(repo.createCategory(named: "Favorite"))
        XCTAssertTrue(repo.addToLibrary(manga, defaultCategory: LibraryPrefs.alwaysAsk))
        repo.setInLibrary(manga, false)
        XCTAssertFalse(repo.addToLibrary(manga, defaultCategory: Int(favorite.id)))
        XCTAssertEqual(repo.categoryIds(of: manga), [favorite.id])
    }

    func testDeletingTheDefaultCategoryResetsThePreference() throws {
        let key = Pref.libraryDefaultCategory.name
        let saved = UserDefaults.standard.object(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        let repo = try LibraryRepository.inMemory()
        let favorite = try XCTUnwrap(repo.createCategory(named: "Favorite"))
        UserDefaults.standard.set(Int(favorite.id), forKey: key)
        repo.deleteCategory(favorite.id)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: key), LibraryPrefs.alwaysAsk)
    }

    func testTriStateAssignment() {
        let checks = CategoryAssignment.initial(categoryIds: [1, 2, 3], selections: [[1, 2], [1]])
        XCTAssertEqual(checks, [1: .on, 2: .mixed, 3: .off])
        XCTAssertEqual(CategoryAssignment.apply(checks, to: [2, 9]), [1, 2, 9])
        XCTAssertEqual(CategoryAssignment.apply([1: .off, 2: .mixed, 3: .on], to: [1, 2]), [2, 3])
        XCTAssertEqual(CategoryAssignment.toggled(.mixed), .on)
        XCTAssertEqual(CategoryAssignment.toggled(.on), .off)
        XCTAssertEqual(CategoryAssignment.toggled(.off), .on)
    }
}
