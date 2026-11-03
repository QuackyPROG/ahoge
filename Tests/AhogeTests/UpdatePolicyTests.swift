import XCTest
@testable import Ahoge

@MainActor
final class UpdatePolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000_000)
    private let day: TimeInterval = 86_400

    private func decide(_ manga: LibraryManga, _ rules: UpdateRules = UpdateRules(), categories: Set<Int64> = []) -> SkipReason? {
        UpdatePolicy.decide(manga, categories: categories, rules: rules, now: now)
    }

    private func title(chapters: Int = 3) throws -> LibraryManga {
        SourceFixture.manga(in: try LibraryRepository.inMemory(), chapters: chapters)
    }

    func testTitleThatPassesEveryRuleIsUpdated() throws {
        XCTAssertNil(decide(try title()))
    }

    func testCompletedTitlesAreSkippedOnlyWhenTheRuleIsOn() throws {
        let manga = try title()
        manga.status = "completed"
        XCTAssertEqual(decide(manga), .completed)
        XCTAssertNil(decide(manga, UpdateRules(skipCompleted: false)))
    }

    func testTitleWithUnreadChaptersIsSkippedWhenAsked() throws {
        let manga = try title()
        XCTAssertNil(decide(manga))
        XCTAssertEqual(decide(manga, UpdateRules(skipUnread: true, skipCompleted: false)), .hasUnread)
    }

    func testTitleNeverReadIsSkippedWhenAsked() throws {
        let repo = try LibraryRepository.inMemory()
        let manga = SourceFixture.manga(in: repo, chapters: 3)
        let rules = UpdateRules(skipUnstarted: true)
        XCTAssertEqual(decide(manga, rules), .notStarted)
        repo.setRead([manga.chapter(1)], true)
        XCTAssertNil(decide(manga, rules))
    }

    func testTitleWithoutChaptersIsNotCalledUnstarted() throws {
        let manga = LibraryManga(sourceId: "s", url: "/m", title: "T", coverUrl: "")
        XCTAssertNil(decide(manga, UpdateRules(skipUnstarted: true)))
    }

    func testExcludedCategorySkipsTheTitle() throws {
        let manga = try title()
        let rules = UpdateRules(excludedCategories: [7])
        XCTAssertEqual(decide(manga, rules, categories: [3, 7]), .excludedCategory)
        XCTAssertNil(decide(manga, rules, categories: [3]))
    }

    func testSmartUpdateWaitsForThePredictedDate() throws {
        let manga = try title()
        manga.nextUpdate = now.addingTimeInterval(3 * day)
        XCTAssertEqual(decide(manga), .notDue)
        XCTAssertNil(decide(manga, UpdateRules(smartUpdate: false)))
        manga.nextUpdate = now.addingTimeInterval(-60)
        XCTAssertNil(decide(manga))
    }

    func testCustomIntervalOverridesThePrediction() throws {
        let manga = try title()
        manga.nextUpdate = now.addingTimeInterval(-day)
        manga.updateInterval = 7
        manga.lastChapterFetch = now.addingTimeInterval(-2 * day)
        XCTAssertEqual(decide(manga), .notDue, "fetched 2 days ago, every 7 days")
        manga.lastChapterFetch = now.addingTimeInterval(-8 * day)
        XCTAssertNil(decide(manga))
    }

    func testIntervalZeroMeansNever() throws {
        let manga = try title()
        manga.updateInterval = 0
        manga.lastChapterFetch = now.addingTimeInterval(-365 * day)
        XCTAssertEqual(decide(manga), .notDue)
        XCTAssertNil(UpdatePolicy.dueDate(manga, rules: UpdateRules()))
    }

    func testWeeklySeriesPredictsAboutSevenDays() {
        let dates = (0..<5).map { Date(timeIntervalSince1970: 1_000_000_000 + Double($0) * 7 * 86_400) }
        XCTAssertEqual(ReleasePredictor.interval(uploadDates: dates), 7 * 86_400)
    }

    func testPredictionUsesTheMedianSoOneLongBreakDoesNotMatter() {
        // Gaps of 7, 7, 60 and 7 days: median 7.
        let offsets: [Double] = [0, 7, 14, 74, 81]
        let dates = offsets.map { Date(timeIntervalSince1970: 1_000_000_000 + $0 * 86_400) }
        XCTAssertEqual(ReleasePredictor.interval(uploadDates: dates), 7 * 86_400)
    }

    func testPredictionIsClampedToOneToTwentyEightDays() {
        let slow = [0, 90, 180].map { Date(timeIntervalSince1970: 1_000_000_000 + Double($0) * 86_400) }
        XCTAssertEqual(ReleasePredictor.interval(uploadDates: slow), 28 * 86_400)
        let fast = [0, 60, 120].map { Date(timeIntervalSince1970: 1_000_000_000 + Double($0)) }
        XCTAssertEqual(ReleasePredictor.interval(uploadDates: fast), 86_400)
    }

    func testFewerThanThreeChaptersGiveNoPrediction() {
        let dates = [0, 7].map { Date(timeIntervalSince1970: 1_000_000_000 + Double($0) * 86_400) }
        XCTAssertNil(ReleasePredictor.interval(uploadDates: dates))
        XCTAssertNil(ReleasePredictor.interval(uploadDates: []))
    }

    func testNextUpdateAddsTheInterval() {
        let last = Date(timeIntervalSince1970: 1_000_000_000)
        XCTAssertEqual(ReleasePredictor.nextUpdate(lastFetch: last, interval: 7 * 86_400), Date(timeIntervalSince1970: 1_000_000_000 + 604_800))
    }
}
