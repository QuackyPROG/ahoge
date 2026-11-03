import XCTest
@testable import Ahoge

final class ReleaseCheckerTests: XCTestCase {
    private func release(_ tag: String, notes: String = "Fixes") -> String {
        #"{"tag_name":"\#(tag)","body":"\#(notes)","html_url":"https://github.com/QuackyPROG/ahoge/releases/tag/\#(tag)"}"#
    }

    func testNewerReleaseIsReturnedWithItsNotes() async throws {
        let transport = StubTransport.text(release("v0.10.0", notes: "New things"))
        let found = try await ReleaseChecker(transport: transport).latest(current: "0.9.0")
        XCTAssertEqual(found, ReleaseInfo(
            version: "0.10.0", notes: "New things",
            pageURL: URL(string: "https://github.com/QuackyPROG/ahoge/releases/tag/v0.10.0")!
        ))
        XCTAssertEqual(transport.requests.first?.url?.absoluteString, "https://api.github.com/repos/QuackyPROG/ahoge/releases/latest")
    }

    func testSameOrOlderReleaseIsNotAnUpdate() async throws {
        let same = try await ReleaseChecker(transport: StubTransport.text(release("v0.4.0"))).latest(current: "0.4.0")
        let older = try await ReleaseChecker(transport: StubTransport.text(release("v0.3.0"))).latest(current: "0.4.0")
        XCTAssertNil(same)
        XCTAssertNil(older)
    }

    func testSkippedVersionIsNotOffered() async throws {
        let skipped = try await ReleaseChecker(transport: StubTransport.text(release("v0.5.0"))).latest(current: "0.4.0", skipping: "0.5.0")
        let later = try await ReleaseChecker(transport: StubTransport.text(release("v0.6.0"))).latest(current: "0.4.0", skipping: "0.5.0")
        XCTAssertNil(skipped)
        XCTAssertEqual(later?.version, "0.6.0")
    }

    func testNoReleasesYetIsNotAnError() async throws {
        let found = try await ReleaseChecker(transport: StubTransport.text("{}", status: 404)).latest(current: "0.4.0")
        XCTAssertNil(found)
    }

    func testServerErrorThrows() async {
        do {
            _ = try await ReleaseChecker(transport: StubTransport.text("", status: 403)).latest(current: "0.4.0")
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error is ReleaseChecker.CheckError)
        }
    }

    func testVersionComparison() {
        XCTAssertTrue(ReleaseChecker.isNewer("0.10.0", than: "0.9.9"))
        XCTAssertTrue(ReleaseChecker.isNewer("1.0", than: "0.9.9"))
        XCTAssertFalse(ReleaseChecker.isNewer("1.0.0", than: "1.0"))
        XCTAssertTrue(ReleaseChecker.isNewer("v0.5.0", than: "0.5.0-beta"))
        XCTAssertFalse(ReleaseChecker.isNewer("0.5.0-beta", than: "0.5.0"))
    }
}
