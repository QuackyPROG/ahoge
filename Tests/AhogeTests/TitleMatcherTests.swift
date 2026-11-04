import XCTest
@testable import Ahoge

final class TitleMatcherTests: XCTestCase {
    private func library(_ titles: [String]) -> [LibraryManga] {
        titles.enumerated().map { LibraryManga(sourceId: "s", url: "/\($0.offset)", title: $0.element, coverUrl: "") }
    }

    private func matches(_ title: String, in titles: [String]) -> [String] {
        TitleMatcher.similar(title, to: library(titles)).map(\.title)
    }

    func testExactTitleMatches() {
        XCTAssertEqual(matches("One Piece", in: ["Bleach", "One Piece"]), ["One Piece"])
    }

    func testCaseAndPunctuationDoNotMatter() {
        XCTAssertEqual(matches("Kaguya-sama: Love is War", in: ["kaguya sama love IS war!"]), ["kaguya sama love IS war!"])
    }

    func testAccentsAndALeadingTheDoNotMatter() {
        XCTAssertEqual(matches("The Promised Neverland", in: ["Promised Neverland"]), ["Promised Neverland"])
        XCTAssertEqual(matches("Pokémon Adventures", in: ["Pokemon Adventures"]), ["Pokemon Adventures"])
    }

    func testSeasonMarkersAreIgnored() {
        XCTAssertEqual(matches("Attack on Titan Season 2", in: ["Attack on Titan"]), ["Attack on Titan"])
        XCTAssertEqual(matches("Mushoku Tensei 2nd Season", in: ["Mushoku Tensei"]), ["Mushoku Tensei"])
    }

    func testADifferentSubtitleStillMatches() {
        XCTAssertEqual(matches("Spy x Family", in: ["Spy x Family: Family Portrait"]), ["Spy x Family: Family Portrait"])
    }

    func testUnrelatedTitlesDoNotMatch() {
        XCTAssertEqual(matches("Berserk", in: ["Bleach", "One Piece", "Vagabond"]), [])
        // A short shared word is not enough.
        XCTAssertEqual(matches("One", in: ["One Piece"]), [])
    }
}
