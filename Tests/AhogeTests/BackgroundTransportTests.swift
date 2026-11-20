import XCTest
@testable import Ahoge

/// The delegate's side of `BackgroundTransport` driven by hand, in the orders URLSession may use.
@MainActor
final class BackgroundTransportTests: XCTestCase {
    /// A task whose completion was delivered before anyone waited for it, so it never reports again.
    private final class SilentTask: TransportTask {
        let taskIdentifier = 1
        func resume() {}
        func cancel() {}
    }

    private final class Flag {
        var value = false
    }

    /// Waits up to two seconds for `flag`.
    private func waitUntil(_ flag: Flag) async throws {
        var tries = 0
        while !flag.value, tries < 200 {
            tries += 1
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testSendCancelledBeforeItWaitsStillReturns() async throws {
        // The download is cancelled after its task is made and before `send` waits on it.
        let transport = BackgroundTransport { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return SilentTask()
        }
        let returned = Flag()
        Task {
            _ = try? await transport.send(URLRequest(url: URL(string: "https://img.test/1.jpg")!))
            returned.value = true
        }
        try await waitUntil(returned)
        XCTAssertTrue(returned.value, "send never returned: its continuation leaked")
    }

    func testEventsFinishedBeforeTheHandlerArrivesStillCallIt() async throws {
        let transport = BackgroundTransport { _ in SilentTask() }
        transport.urlSessionDidFinishEvents(forBackgroundURLSession: URLSession.shared)
        let called = Flag()
        transport.setEventsCompletionHandler { called.value = true }
        try await waitUntil(called)
        XCTAssertTrue(called.value, "the system's completion handler was never called")
    }
}
