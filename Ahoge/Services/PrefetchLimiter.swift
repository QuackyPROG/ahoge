import UIKit

/// Runs reader prefetches at most `limit` at a time, in the order they came, so a fast scroll
/// never starts dozens of decodes at once. A key already waiting or running is not added again.
actor PrefetchLimiter {
    static let shared: PrefetchLimiter = {
        let limiter = PrefetchLimiter(limit: 2)
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { _ in
            Task { await limiter.cancelAll() }
        }
        return limiter
    }()

    private let limit: Int
    private var running: Set<String> = []
    private var waiting: [(key: String, job: @Sendable () async -> Void)] = []

    init(limit: Int) { self.limit = limit }

    func enqueue(_ key: String, _ job: @escaping @Sendable () async -> Void) {
        guard !running.contains(key), !waiting.contains(where: { $0.key == key }) else { return }
        waiting.append((key, job))
        startWaiting()
    }

    /// Drops the jobs that have not started; running ones finish.
    func cancelAll() { waiting.removeAll() }

    private func startWaiting() {
        while running.count < limit, !waiting.isEmpty {
            let next = waiting.removeFirst()
            running.insert(next.key)
            Task(priority: .utility) {
                await next.job()
                self.finished(next.key)
            }
        }
    }

    private func finished(_ key: String) {
        running.remove(key)
        startWaiting()
    }
}
