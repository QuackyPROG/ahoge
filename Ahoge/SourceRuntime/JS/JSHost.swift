import Foundation
import JavaScriptCore

/// Resumes a continuation at most once (the result, an error or the timeout, whichever comes first).
private final class Once<T> {
    private var continuation: CheckedContinuation<T, Error>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) { take()?.resume(returning: value) }
    func resume(throwing error: Error) { take()?.resume(throwing: error) }

    private func take() -> CheckedContinuation<T, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let c = continuation
        continuation = nil
        return c
    }
}

/// One JavaScriptCore context running one source bundle, confined to a serial queue.
final class JSHost {
    static let runtimeVersion = 1

    let http: HTTPClient
    private let context: JSContext
    private let queue = DispatchQueue(label: "ahoge.jshost")
    private let log: (String) -> Void
    private var source: JSValue?

    init(script: String, http: HTTPClient = HTTPClient(), log: @escaping (String) -> Void = { _ in }) throws {
        guard let context = JSContext() else { throw SourceError.script("JavaScriptCore is unavailable") }
        self.context = context
        self.http = http
        self.log = log
        try queue.sync {
            installNatives()
            context.evaluateScript(JSBootstrap.source)
            if let exception = context.exception { throw SourceError.script("bootstrap: \(exception)") }
            context.evaluateScript(script, withSourceURL: URL(string: "ahoge://source.js"))
            if let exception = context.exception {
                context.exception = nil
                throw SourceError.script(Self.message(of: exception))
            }
            guard let value = context.objectForKeyedSubscript("source"), value.isObject else { throw SourceError.noSourceAssigned }
            source = value
        }
    }

    /// Evaluates JavaScript and returns its string value. For tests and diagnostics.
    func evaluate(_ js: String) -> String? {
        queue.sync {
            context.exception = nil
            let value = context.evaluateScript(js)
            if let exception = context.exception {
                context.exception = nil
                return "exception: \(exception)"
            }
            return value?.toString()
        }
    }

    /// Calls `source[method](...arguments)`, awaits its promise, and returns the JSON-serialized result.
    func call(_ method: String, _ arguments: [Any], timeout: TimeInterval = 30) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let once = Once(continuation)
            queue.async {
                guard let source = self.source,
                      let function = source.objectForKeyedSubscript(method),
                      function.isInstance(of: self.context.objectForKeyedSubscript("Function")) else {
                    once.resume(throwing: SourceError.missingMethod(method))
                    return
                }
                self.context.exception = nil
                let result = source.invokeMethod(method, withArguments: arguments)
                if let exception = self.context.exception {
                    self.context.exception = nil
                    once.resume(throwing: self.error(from: exception))
                    return
                }
                let onFulfilled: @convention(block) (JSValue) -> Void = { value in
                    let json = self.context.objectForKeyedSubscript("JSON").invokeMethod("stringify", withArguments: [value as Any])
                    let text = (json == nil || json!.isUndefined) ? "null" : json!.toString()!
                    once.resume(returning: Data(text.utf8))
                }
                let onRejected: @convention(block) (JSValue) -> Void = { reason in
                    once.resume(throwing: self.error(from: reason))
                }
                let promise = self.context.objectForKeyedSubscript("Promise").invokeMethod("resolve", withArguments: [result as Any])
                promise?.invokeMethod("then", withArguments: [
                    JSValue(object: onFulfilled, in: self.context) as Any,
                    JSValue(object: onRejected, in: self.context) as Any,
                ])
            }
            queue.asyncAfter(deadline: .now() + timeout) {
                once.resume(throwing: SourceError.timeout("Source call \(method) timed out after \(Int(timeout * 1000)) ms"))
            }
        }
    }

    // MARK: - Natives

    private func installNatives() {
        let httpNative: @convention(block) (String, String, JSValue, JSValue) -> JSValue = { [weak self] method, url, headersValue, bodyValue in
            let context = JSContext.current()!
            let headers = (headersValue.toDictionary() as? [String: Any] ?? [:]).mapValues { "\($0)" }
            let body: Data? = (bodyValue.isNull || bodyValue.isUndefined) ? nil : Data(bodyValue.toString().utf8)
            return JSValue(newPromiseIn: context) { resolve, reject in
                guard let self, let resolve, let reject else { return }
                let spec = HTTPRequestSpec(method: method, url: url, headers: headers, body: body)
                Task {
                    do {
                        let response = try await self.http.send(spec)
                        self.queue.async { resolve.call(withArguments: [self.responseObject(response)]) }
                    } catch HTTPClientError.cloudflare(let challengeURL) {
                        self.queue.async {
                            let error = self.context.objectForKeyedSubscript("CloudflareError").construct(withArguments: [challengeURL])
                            reject.call(withArguments: [error as Any])
                        }
                    } catch {
                        self.queue.async {
                            reject.call(withArguments: [JSValue(newErrorFromMessage: error.localizedDescription, in: self.context) as Any])
                        }
                    }
                }
            }
        }
        let parse: @convention(block) (String, String) -> JSElement? = { body, baseUrl in
            do {
                return JSElement(try HTMLNode.parse(body, baseUrl: baseUrl))
            } catch {
                JSElement.raise(error)
                return nil
            }
        }
        let logNative: @convention(block) (String) -> Void = { [weak self] line in self?.log(line) }
        let atob: @convention(block) (JSValue) -> JSValue = { input in
            Self.base64(input) { try Base64Latin1.atob($0) }
        }
        let btoa: @convention(block) (JSValue) -> JSValue = { input in
            Self.base64(input) { try Base64Latin1.btoa($0) }
        }
        context.setObject(unsafeBitCast(httpNative, to: AnyObject.self), forKeyedSubscript: "__ahoge_http" as NSString)
        context.setObject(unsafeBitCast(parse, to: AnyObject.self), forKeyedSubscript: "__ahoge_parse" as NSString)
        context.setObject(unsafeBitCast(logNative, to: AnyObject.self), forKeyedSubscript: "__ahoge_log" as NSString)
        context.setObject(unsafeBitCast(atob, to: AnyObject.self), forKeyedSubscript: "atob" as NSString)
        context.setObject(unsafeBitCast(btoa, to: AnyObject.self), forKeyedSubscript: "btoa" as NSString)
    }

    private static func base64(_ input: JSValue, _ transform: (String) throws -> String) -> JSValue {
        let context = JSContext.current()!
        do {
            return JSValue(object: try transform(input.toString()), in: context)
        } catch {
            let exception = JSValue(newErrorFromMessage: "The string contains invalid characters.", in: context)!
            exception.setValue("InvalidCharacterError", forProperty: "name")
            context.exception = exception
            return JSValue(undefinedIn: context)
        }
    }

    private func responseObject(_ response: HTTPResponseData) -> JSValue {
        JSValue(object: [
            "status": response.status,
            "url": response.url,
            "headers": response.headers,
            "body": response.body,
        ], in: context)
    }

    private func error(from value: JSValue) -> Error {
        if value.objectForKeyedSubscript("name")?.toString() == "CloudflareError",
           let url = value.objectForKeyedSubscript("url")?.toString() {
            return SourceError.cloudflare(url: url)
        }
        return SourceError.script(Self.message(of: value))
    }

    private static func message(of value: JSValue) -> String {
        if let message = value.objectForKeyedSubscript("message"), !message.isUndefined, let text = message.toString() {
            return text
        }
        return value.toString() ?? "Unknown script error"
    }
}
