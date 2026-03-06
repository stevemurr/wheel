import Foundation
import JavaScriptCore
import UserNotifications

/// Sandboxed JavaScriptCore environment for executing module background scripts.
/// Provides the `wheel.*` API (fetch, storage, render, schedule, notify) without DOM access.
final class WheelJSContext: @unchecked Sendable {
    private let context: JSContext
    private let lock = NSLock()
    private let moduleId: UUID
    private let permissions: [ModulePermission]

    /// Storage for this module (persisted to disk).
    private var storage: [String: Any] = [:]
    private let storageURL: URL

    /// The last render output from wheel.render().
    private(set) var lastRenderOutput: [String: Any]?

    /// The result from wheel.result() (for skill modules).
    private(set) var lastResult: Any?

    /// Rate limiting for network requests
    private var requestTimestamps: [Date] = []
    private static let maxRequestsPerMinute = 10

    init(moduleId: UUID, permissions: [ModulePermission]) {
        self.moduleId = moduleId
        self.permissions = permissions

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storageDir = appSupport.appendingPathComponent("WheelBrowser/module_storage")
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        self.storageURL = storageDir.appendingPathComponent("\(moduleId.uuidString).json")

        // Load persisted storage
        if let data = try? Data(contentsOf: storageURL),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            self.storage = dict
        }

        let ctx = JSContext()!

        // Strip dangerous globals
        let dangerousGlobals = [
            "fetch", "XMLHttpRequest", "WebSocket", "Worker",
            "importScripts", "eval", "Function", "Proxy", "Reflect",
        ]
        for name in dangerousGlobals {
            ctx.setObject(nil, forKeyedSubscript: name as NSString)
        }

        ctx.exceptionHandler = { _, exception in
            if let exception {
                Log.Widgets.error("Module JSContext exception: \(exception)")
            }
        }

        self.context = ctx
        injectAPIs()
    }

    /// Execute a background script and return the result.
    func execute(script: String, params: [String: Any]? = nil) async throws -> Any? {
        // Reset result before execution
        lastResult = nil

        return try await withCheckedThrowingContinuation { continuation in
            // 5 second timeout
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                continuation.resume(throwing: ModuleRuntimeError.timeout)
            }

            lock.lock()
            defer { lock.unlock() }

            // Inject params if provided
            if let params {
                context.setObject(params, forKeyedSubscript: "__params" as NSString)
            }

            context.evaluateScript("""
                (async function() {
                    try {
                        \(script)
                    } catch(e) {
                        __reportError(e.message || String(e));
                    }
                })();
            """)

            timeoutTask.cancel()

            if let exception = context.exception {
                context.exception = nil
                continuation.resume(throwing: ModuleRuntimeError.executionFailed(exception.toString() ?? "Unknown JS error"))
            } else {
                continuation.resume(returning: lastResult ?? lastRenderOutput)
            }
        }
    }

    // MARK: - API Injection

    private func injectAPIs() {
        // Create wheel namespace
        context.evaluateScript("var wheel = {};")

        // Error reporting
        let reportError: @convention(block) (String) -> Void = { message in
            Log.Widgets.error("Module \(self.moduleId): \(message)")
        }
        context.setObject(reportError, forKeyedSubscript: "__reportError" as NSString)

        // Storage API
        if permissions.contains(.storageLocal) {
            injectStorageAPI()
        }

        // Network fetch API
        if permissions.contains(.networkFetch) {
            injectFetchAPI()
        }

        // Render API (for widgets)
        injectRenderAPI()

        // Schedule API
        if permissions.contains(.schedule) {
            injectScheduleAPI()
        }

        // Notification API
        if permissions.contains(.notifications) {
            injectNotifyAPI()
        }

        // Messaging API
        injectMessagingAPI()

        // Result API (for skills)
        injectResultAPI()
    }

    private func injectStorageAPI() {
        context.evaluateScript("wheel.storage = {};")

        let storageGet: @convention(block) (String) -> Any? = { [weak self] key in
            return self?.storage[key]
        }
        context.objectForKeyedSubscript("wheel" as NSString)
            .objectForKeyedSubscript("storage" as NSString)
            .setObject(storageGet, forKeyedSubscript: "get" as NSString)

        let storageSet: @convention(block) (String, JSValue) -> Void = { [weak self] key, value in
            guard let self else { return }
            // Quota enforcement
            let currentSize = self.storage.values.reduce(0) { acc, val in
                acc + "\(val)".utf8.count
            }
            let newValue = value.toObject()
            let newSize = "\(newValue ?? "")".utf8.count
            guard currentSize + newSize <= 524_288 else {
                Log.Widgets.error("Module \(self.moduleId): Storage quota exceeded (512KB)")
                return
            }
            self.storage[key] = newValue
            self.persistStorage()
        }
        context.objectForKeyedSubscript("wheel" as NSString)
            .objectForKeyedSubscript("storage" as NSString)
            .setObject(storageSet, forKeyedSubscript: "set" as NSString)

        let storageRemove: @convention(block) (String) -> Void = { [weak self] key in
            self?.storage.removeValue(forKey: key)
            self?.persistStorage()
        }
        context.objectForKeyedSubscript("wheel" as NSString)
            .objectForKeyedSubscript("storage" as NSString)
            .setObject(storageRemove, forKeyedSubscript: "remove" as NSString)
    }

    private func injectFetchAPI() {
        let moduleId = self.moduleId

        let fetchFn: @convention(block) (String, JSValue?) -> JSValue = { [weak self] urlString, options in
            guard let self else { return JSValue(nullIn: JSContext()) }

            // Rate limiting
            let now = Date()
            self.requestTimestamps = self.requestTimestamps.filter {
                now.timeIntervalSince($0) < 60
            }
            guard self.requestTimestamps.count < Self.maxRequestsPerMinute else {
                Log.Widgets.error("Module \(moduleId): Rate limit exceeded (10 req/min)")
                return JSValue(nullIn: self.context)
            }

            // HTTPS only
            guard let url = URL(string: urlString), url.scheme == "https" else {
                Log.Widgets.error("Module \(moduleId): Only HTTPS URLs are allowed")
                return JSValue(nullIn: self.context)
            }

            self.requestTimestamps.append(now)

            // Synchronous fetch (JSContext doesn't support async natively)
            var result: Any?
            let semaphore = DispatchSemaphore(value: 0)

            var request = URLRequest(url: url)
            request.timeoutInterval = 30

            if let opts = options, !opts.isUndefined {
                if let method = opts.objectForKeyedSubscript("method")?.toString() {
                    request.httpMethod = method
                }
                if let headers = opts.objectForKeyedSubscript("headers")?.toDictionary() as? [String: String] {
                    for (key, value) in headers {
                        request.setValue(value, forHTTPHeaderField: key)
                    }
                }
                if let body = opts.objectForKeyedSubscript("body")?.toString(),
                   body != "undefined" {
                    request.httpBody = body.data(using: .utf8)
                }
            }

            URLSession.shared.dataTask(with: request) { data, _, error in
                defer { semaphore.signal() }
                guard let data, error == nil else { return }

                // 1MB response cap
                guard data.count <= 1_048_576 else {
                    Log.Widgets.error("Module \(moduleId): Response exceeds 1MB cap")
                    return
                }

                if let json = try? JSONSerialization.jsonObject(with: data) {
                    result = json
                } else {
                    result = String(data: data, encoding: .utf8)
                }
            }.resume()

            semaphore.wait()
            return result.flatMap { JSValue(object: $0, in: self.context) } ?? JSValue(nullIn: self.context)
        }

        context.objectForKeyedSubscript("wheel" as NSString)
            .setObject(fetchFn, forKeyedSubscript: "fetch" as NSString)
    }

    private func injectRenderAPI() {
        let renderFn: @convention(block) (JSValue) -> Void = { [weak self] renderSpec in
            guard let dict = renderSpec.toDictionary() as? [String: Any] else { return }
            self?.lastRenderOutput = dict
        }
        context.evaluateScript("wheel.render = function() {};")
        context.objectForKeyedSubscript("wheel" as NSString)
            .setObject(renderFn, forKeyedSubscript: "render" as NSString)
    }

    private func injectScheduleAPI() {
        context.evaluateScript("""
            wheel.schedule = {
                setInterval: function(callback, ms) {
                    // Min 5 minutes
                    const interval = Math.max(ms, 300000);
                    return setInterval(callback, interval);
                }
            };
        """)
    }

    private func injectNotifyAPI() {
        let notifyFn: @convention(block) (String, String) -> Void = { title, body in
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
        context.objectForKeyedSubscript("wheel" as NSString)
            .setObject(notifyFn, forKeyedSubscript: "notify" as NSString)
    }

    private func injectMessagingAPI() {
        context.evaluateScript("""
            wheel.message = {
                _handlers: {},
                send: function(type, data) {
                    // Messages are dispatched to content script via Swift bridge
                },
                on: function(type, callback) {
                    if (!this._handlers[type]) this._handlers[type] = [];
                    this._handlers[type].push(callback);
                },
                _dispatch: function(type, data) {
                    (this._handlers[type] || []).forEach(function(cb) { cb(data); });
                }
            };
        """)
    }

    private func injectResultAPI() {
        let resultFn: @convention(block) (JSValue) -> Void = { [weak self] value in
            self?.lastResult = value.toObject()
        }
        context.objectForKeyedSubscript("wheel" as NSString)
            .setObject(resultFn, forKeyedSubscript: "result" as NSString)
    }

    // MARK: - Storage Persistence

    private func persistStorage() {
        do {
            let data = try JSONSerialization.data(withJSONObject: storage)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            Log.Widgets.error("Failed to persist module storage for \(moduleId)", error: error)
        }
    }
}
