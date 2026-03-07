import Foundation
import WebKit

final class WidgetFetchSchemeHandler: NSObject, WKURLSchemeHandler {
    struct DecodedRequest: Equatable {
        let widgetID: UUID
        let remoteURL: URL
    }

    private let session: URLSession
    private let lock = NSLock()
    private var allowedHostsByWidgetID: [UUID: Set<String>] = [:]
    private var runningTasks: [ObjectIdentifier: URLSessionTask] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func updateAllowedHosts(for manifests: [WidgetManifest]) {
        let mapping = Dictionary(uniqueKeysWithValues: manifests.map { ($0.id, $0.allowedHosts) })
        lock.lock()
        allowedHostsByWidgetID = mapping
        lock.unlock()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let requestKey = ObjectIdentifier(urlSchemeTask as AnyObject)

        do {
            guard let requestURL = urlSchemeTask.request.url else {
                throw WidgetManifestValidationError.invalidFetchURL("", "Missing widget fetch URL.")
            }

            let decoded = try Self.decodeRequest(from: requestURL)
            try validate(decoded)

            var request = URLRequest(url: decoded.remoteURL)
            request.timeoutInterval = 10

            let task = session.dataTask(with: request) { [weak self] data, response, error in
                self?.finish(
                    urlSchemeTask: urlSchemeTask,
                    requestURL: requestURL,
                    requestKey: requestKey,
                    data: data,
                    response: response,
                    error: error
                )
            }

            lock.lock()
            runningTasks[requestKey] = task
            lock.unlock()

            task.resume()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        let requestKey = ObjectIdentifier(urlSchemeTask as AnyObject)
        lock.lock()
        let task = runningTasks.removeValue(forKey: requestKey)
        lock.unlock()
        task?.cancel()
    }

    static func decodeRequest(from url: URL) throws -> DecodedRequest {
        guard url.scheme == "widget-fetch" else {
            throw WidgetManifestValidationError.invalidFetchURL(
                url.absoluteString,
                "Unexpected widget fetch scheme."
            )
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard url.host == "request",
              let widgetIDString = pathComponents.first,
              let widgetID = UUID(uuidString: widgetIDString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let remoteURLValue = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let remoteURL = URL(string: remoteURLValue) else {
            throw WidgetManifestValidationError.invalidFetchURL(
                url.absoluteString,
                "Malformed widget fetch request."
            )
        }

        return DecodedRequest(widgetID: widgetID, remoteURL: remoteURL)
    }

    private func validate(_ request: DecodedRequest) throws {
        try WidgetNetworkPolicy.validateRemoteURL(request.remoteURL)

        guard let host = request.remoteURL.host?.lowercased() else {
            throw WidgetManifestValidationError.invalidFetchURL(
                request.remoteURL.absoluteString,
                "Widget fetches must target a valid host."
            )
        }

        let allowedHosts: Set<String>
        lock.lock()
        allowedHosts = allowedHostsByWidgetID[request.widgetID] ?? []
        lock.unlock()

        guard allowedHosts.contains(host) else {
            throw WidgetManifestValidationError.invalidFetchURL(
                request.remoteURL.absoluteString,
                "Host '\(host)' is not in this widget's allowlist."
            )
        }
    }

    private func finish(
        urlSchemeTask: any WKURLSchemeTask,
        requestURL: URL,
        requestKey: ObjectIdentifier,
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) {
        lock.lock()
        runningTasks.removeValue(forKey: requestKey)
        lock.unlock()

        if let error {
            urlSchemeTask.didFailWithError(error)
            return
        }

        let body = data ?? Data()
        let proxiedResponse: HTTPURLResponse

        if let httpResponse = response as? HTTPURLResponse {
            var headers: [String: String] = [:]
            for (key, value) in httpResponse.allHeaderFields {
                headers[String(describing: key)] = String(describing: value)
            }
            headers["Access-Control-Allow-Origin"] = "*"
            proxiedResponse = HTTPURLResponse(
                url: requestURL,
                statusCode: httpResponse.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
        } else {
            proxiedResponse = HTTPURLResponse(
                url: requestURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "application/octet-stream",
                    "Access-Control-Allow-Origin": "*",
                ]
            )!
        }

        urlSchemeTask.didReceive(proxiedResponse)
        urlSchemeTask.didReceive(body)
        urlSchemeTask.didFinish()
    }
}
