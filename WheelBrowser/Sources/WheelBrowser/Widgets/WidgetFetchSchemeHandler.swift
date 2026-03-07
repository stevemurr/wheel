import Foundation
import WebKit

final class WidgetFetchSchemeHandler: NSObject, WKURLSchemeHandler {
    struct DecodedRequest: Equatable {
        let widgetID: UUID
        let remoteURL: URL
        let method: String
        let headers: [String: String]
        let body: Data?
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
            request.httpMethod = decoded.method
            if decoded.method == "POST" {
                request.httpBody = decoded.body
            }
            for (header, value) in decoded.headers where !Self.isBlockedForwardHeader(header) {
                request.setValue(value, forHTTPHeaderField: header)
            }

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

        let queryItems = components.queryItems ?? []
        let method = (queryItems.first(where: { $0.name == "method" })?.value ?? "GET").uppercased()
        guard method == "GET" || method == "POST" else {
            throw WidgetManifestValidationError.invalidFetchURL(
                url.absoluteString,
                "Widget fetches only support GET and POST."
            )
        }

        let headers: [String: String]
        if let rawHeaders = queryItems.first(where: { $0.name == "headers" })?.value {
            headers = try decodeHeaders(rawHeaders, requestURL: url)
        } else {
            headers = [:]
        }

        let body: Data?
        if let rawBody = queryItems.first(where: { $0.name == "body" })?.value {
            body = try decodeBody(rawBody, requestURL: url)
        } else {
            body = nil
        }

        if body != nil, method != "POST" {
            throw WidgetManifestValidationError.invalidFetchURL(
                url.absoluteString,
                "Widget fetch bodies require POST."
            )
        }

        return DecodedRequest(
            widgetID: widgetID,
            remoteURL: remoteURL,
            method: method,
            headers: headers,
            body: body
        )
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

    private static func decodeHeaders(_ encoded: String, requestURL: URL) throws -> [String: String] {
        guard let data = Data(base64Encoded: encoded),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WidgetManifestValidationError.invalidFetchURL(
                requestURL.absoluteString,
                "Malformed widget fetch headers payload."
            )
        }

        var headers: [String: String] = [:]
        for (key, value) in object {
            guard let stringValue = value as? String else {
                throw WidgetManifestValidationError.invalidFetchURL(
                    requestURL.absoluteString,
                    "Widget fetch headers must be string values."
                )
            }
            headers[key] = stringValue
        }
        return headers
    }

    private static func decodeBody(_ encoded: String, requestURL: URL) throws -> Data {
        guard let data = Data(base64Encoded: encoded) else {
            throw WidgetManifestValidationError.invalidFetchURL(
                requestURL.absoluteString,
                "Malformed widget fetch body payload."
            )
        }
        return data
    }

    private static func isBlockedForwardHeader(_ header: String) -> Bool {
        switch header.lowercased() {
        case "host", "origin", "content-length":
            return true
        default:
            return false
        }
    }
}
