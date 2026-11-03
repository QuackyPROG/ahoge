import Foundation

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

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// The app delegate hands this over when iOS wakes the app for our session's events.
    func setEventsCompletionHandler(_ handler: @escaping () -> Void) {
        lock.withLock { finishEvents = handler }
        _ = session
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let task = session.downloadTask(with: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock { waiting[task.taskIdentifier] = continuation }
                task.resume()
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
        let handler = lock.withLock {
            let handler = finishEvents
            finishEvents = nil
            return handler
        }
        DispatchQueue.main.async { handler?() }
    }
}
