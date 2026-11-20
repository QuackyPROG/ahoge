import XCTest
@testable import Ahoge

final class PrefetchLimiterTests: XCTestCase {
    /// Jobs that record how many run at once and wait until the test opens the gate.
    private actor Probe {
        private(set) var running = 0
        private(set) var most = 0
        private(set) var started: [String] = []
        private(set) var finished = 0
        private var open = false

        func run(_ key: String) async {
            running += 1
            most = max(most, running)
            started.append(key)
            while !open { try? await Task.sleep(nanoseconds: 5_000_000) }
            running -= 1
            finished += 1
        }

        func openGate() { open = true }
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<400 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("timed out")
    }

    func testAtMostTwoRunAtOnceInOrderWithoutDuplicates() async throws {
        let limiter = PrefetchLimiter(limit: 2)
        let probe = Probe()
        for key in ["0", "1", "2", "3", "4", "5", "0", "5"] {
            await limiter.enqueue(key) { await probe.run(key) }
        }
        try await waitUntil { await probe.started.count == 2 }
        try await Task.sleep(nanoseconds: 100_000_000)
        let early = await probe.started
        XCTAssertEqual(early, ["0", "1"])
        await probe.openGate()
        try await waitUntil { await probe.finished == 6 }
        try await Task.sleep(nanoseconds: 100_000_000)
        let started = await probe.started
        let most = await probe.most
        XCTAssertEqual(started, ["0", "1", "2", "3", "4", "5"])
        XCTAssertEqual(most, 2)
    }

    func testCancelAllDropsTheWaitingJobs() async throws {
        let limiter = PrefetchLimiter(limit: 2)
        let probe = Probe()
        for key in ["0", "1", "2", "3"] {
            await limiter.enqueue(key) { await probe.run(key) }
        }
        try await waitUntil { await probe.started.count == 2 }
        await limiter.cancelAll()
        await probe.openGate()
        try await waitUntil { await probe.finished == 2 }
        try await Task.sleep(nanoseconds: 100_000_000)
        let started = await probe.started
        XCTAssertEqual(started, ["0", "1"])
    }
}
