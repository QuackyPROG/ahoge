import XCTest
@testable import Ahoge

@MainActor
final class MigrationPickTests: XCTestCase {
    private let target = MangaRef(sourceId: "en.other", url: "/m/1", title: "One", cover: "")

    func testPickingAResultHoldsTheOldEntryFoundAtTapTime() throws {
        let repo = try LibraryRepository.inMemory()
        let old = repo.upsert(sourceId: "en.demo", url: "/m/1", title: "One", cover: "")
        repo.setInLibrary(old, true)
        let pick = MigrationPick.make(migrating: old.ref, target: target, repo: repo)
        XCTAssertTrue(pick?.old === old)
        XCTAssertEqual(pick?.target, target)
    }

    func testPickingAResultForAnEntryThatIsGoneGivesNothing() throws {
        let repo = try LibraryRepository.inMemory()
        let gone = MangaRef(sourceId: "en.demo", url: "/m/gone", title: "Gone", cover: "")
        XCTAssertNil(MigrationPick.make(migrating: gone, target: target, repo: repo))
    }

    func testPickingAResultForAnEntryNoLongerInTheLibraryGivesNothing() throws {
        let repo = try LibraryRepository.inMemory()
        let old = repo.upsert(sourceId: "en.demo", url: "/m/1", title: "One", cover: "")
        repo.setInLibrary(old, false)
        XCTAssertNil(MigrationPick.make(migrating: old.ref, target: target, repo: repo))
    }
}
