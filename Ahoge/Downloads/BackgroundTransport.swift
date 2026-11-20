import Foundation

/// What `BackgroundTransport.send` needs of a session task; tests stand in a fake.
protocol TransportTask: AnyObject {
    var taskIdentifier: Int { get }
    func resume()
    func cancel()
}

extension URLSessionDownloadTask: TransportTask {}

/// An `HTTPTransport` over a background `URLSession`, so page files keep arriving while the app is
/// suspended. Background sessions only run download tasks, so each request becomes one and its file
/// is read back into memory when it lands. `DownloadManager` uses it only while the app is in the
/// background; the foreground path stays on the ordinary transport.
///
/// Hand-check on a device: start downloading five chapters, lock the phone, come back.
final class BackgroundTransport: NSObject, HTTPTransport, URLSessionDownloadDelegate, @unchecked Sendable {
    static let identifier = "com.quackyprog.ahoge.downloads"
    static let shared = BackgroundTransport()

    private let lock = NSLock()
    private var waiting: [Int: CheckedContinuation<(Data, HTTPURLResponse), Error>] = [:]
    private var landed: [Int: Data] = [:]
    private var finishEvents: (() -> Void)?
    private var eventsFinished = false

    /// Set once in `init`; a session with this identifier must exist only once per process.
    private var session: URLSession!
    private var makeTask: ((URLRequest) -> TransportTask)!

    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        makeTask = { [unowned self] in self.session.downloadTask(with: $0) }
    }

    /// For tests: no background session; `send` runs the tasks `makeTask` returns.
    init(makeTask: @escaping (URLRequest) -> TransportTask) {
        super.init()
        self.makeTask = makeTask
    }

    /// The app delegate hands this over when iOS wakes the app for our session's events.
    func setEventsCompletionHandler(_ handler: @escaping () -> Void) {
        let finished = lock.withLock { () -> Bool in
            if eventsFinished {
                eventsFinished = false
                return true
            }
            finishEvents = handler
            return false
        }
        if finished { DispatchQueue.main.async(execute: handler) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let task = makeTask(request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Cancelled before this point, the task's completion may already have gone by with no one waiting.
                let cancelled = lock.withLock { () -> Bool in
                    guard !Task.isCancelled else { return true }
                    waiting[task.taskIdentifier] = continuation
                    return false
                }
                if cancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    task.resume()
                }
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The file is deleted as soon as this returns.
        let data = try? Data(contentsOf: location)
        lock.withLock { landed[downloadTask.taskIdentifier] = data }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (continuation, data) = lock.withLock {
            (waiting.removeValue(forKey: task.taskIdentifier), landed.removeValue(forKey: task.taskIdentifier))
        }
        // Tasks left over from a previous launch have no one waiting.
        guard let continuation else { return }
        if let error {
            continuation.resume(throwing: error)
        } else if let response = task.response as? HTTPURLResponse, let data {
            continuation.resume(returning: (data, response))
        } else {
            continuation.resume(throwing: URLError(.badServerResponse))
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let handler = lock.withLock { () -> (() -> Void)? in
            let pending = finishEvents
            finishEvents = nil
            // The session can finish before the app delegate hands the handler over; it is called then.
            eventsFinished = pending == nil
            return pending
        }
        DispatchQueue.main.async { handler?() }
    }
}
