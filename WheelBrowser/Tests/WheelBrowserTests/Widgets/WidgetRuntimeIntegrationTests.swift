import Foundation
import Testing
import WebKit
@testable import WheelBrowser

@Suite("WidgetRuntimeIntegration")
struct WidgetRuntimeIntegrationTests {
    @MainActor
    @Test("Dashboard bootstraps and renders a text widget")
    func bootstrapsAndRendersText() async throws {
        let harness = try WidgetRuntimeHarness()
        harness.load()
        try await harness.waitUntilReady()

        let manifest = textWidgetManifest(title: "Greeting", content: "Hello from runtime")
        harness.bootstrap([manifest])
        try await harness.waitUntilLoaded(id: manifest.id)

        let rendered = try await harness.pageText()
        #expect(rendered.contains("Hello from runtime"))
    }

    @MainActor
    @Test("Runtime emits widget errors")
    func emitsWidgetErrors() async throws {
        let harness = try WidgetRuntimeHarness()
        harness.load()
        try await harness.waitUntilReady()

        let manifest = WidgetManifest(
            widgetType: .text,
            config: .text(TextConfig(title: "Broken", markdown: false)),
            skillChain: [
                WidgetSkillStep(
                    step: 1,
                    skill: .parseJson,
                    params: ["json": AnyCodable("not-json")],
                    outputKey: "bad"
                ),
            ],
            returns: "bad",
            ttl: 300,
            prompt: "Broken"
        )

        harness.bootstrap([manifest])
        try await waitUntil {
            harness.errors[manifest.id] != nil
        }

        #expect(harness.errors[manifest.id]?.contains("JSON") == true)
    }

    @MainActor
    @Test("Runtime forwards open link actions")
    func forwardsOpenLinkActions() async throws {
        let harness = try WidgetRuntimeHarness()
        harness.load()
        try await harness.waitUntilReady()

        let manifest = textWidgetManifest(
            title: "Docs",
            content: "[Open](https://example.com)",
            markdown: true
        )
        harness.bootstrap([manifest])
        try await harness.waitUntilLoaded(id: manifest.id)

        _ = try await harness.webView.evaluateJavaScript(
            "document.querySelector('a[href]')?.click(); true;"
        )

        try await waitUntil {
            !harness.actions.isEmpty
        }

        guard case .openLink(let widgetID, let url) = harness.actions.last else {
            Issue.record("Expected openLink action")
            return
        }

        #expect(widgetID == manifest.id)
        #expect(url.host == "example.com")
    }

    @MainActor
    @Test("Runtime cache avoids repeated fetches within TTL")
    func cacheAvoidsRepeatedFetches() async throws {
        MockWidgetURLProtocol.requestCount = 0
        MockWidgetURLProtocol.responseData = Data(#"{"value":42}"#.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockWidgetURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let harness = try WidgetRuntimeHarness(session: session)
        harness.load()
        try await harness.waitUntilReady()

        let manifest = fetchWidgetManifest(url: "https://api.example.com/value")
        harness.bootstrap([manifest])
        try await harness.waitUntilLoadedCount(1, for: manifest.id)

        harness.bridge.setDashboardState(
            records: [WidgetRecord(manifest: manifest, position: 0, lastLoadedAt: nil, lastError: nil)],
            isEditing: false
        )
        try await harness.waitUntilLoadedCount(2, for: manifest.id)

        #expect(MockWidgetURLProtocol.requestCount == 1)
    }
}

@MainActor
private final class WidgetRuntimeHarness {
    let bridge = WidgetRuntimeBridge()
    let schemeHandler: WidgetFetchSchemeHandler
    let webView: WKWebView
    var ready = false
    var loadedIDs: [UUID] = []
    var errors: [UUID: String] = [:]
    var actions: [WidgetRuntimeAction] = []

    init(session: URLSession = .shared) throws {
        schemeHandler = WidgetFetchSchemeHandler(session: session)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: "widget-fetch")
        configuration.userContentController.add(bridge, name: "widgetBridge")
        webView = WKWebView(frame: .zero, configuration: configuration)
        bridge.attach(to: webView)
        bridge.onReady = { [weak self] in self?.ready = true }
        bridge.onWidgetLoaded = { [weak self] id in self?.loadedIDs.append(id) }
        bridge.onWidgetError = { [weak self] id, message in self?.errors[id] = message }
        bridge.onWidgetAction = { [weak self] action in self?.actions.append(action) }
    }

    func load() {
        guard let baseURL = WidgetRuntimeResources.runtimeDirectoryURL(),
              let scriptURL = WidgetRuntimeResources.runtimeScriptURL(),
              let stylesURL = WidgetRuntimeResources.runtimeStylesURL(),
              let script = try? String(contentsOf: scriptURL, encoding: .utf8),
              let styles = try? String(contentsOf: stylesURL, encoding: .utf8) else {
            Issue.record("Missing widget runtime resource")
            return
        }
        let html = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>\(styles)</style>
        </head>
        <body>
          <main id="dashboard" class="dashboard"></main>
          <script>\(script)</script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func bootstrap(_ manifests: [WidgetManifest]) {
        schemeHandler.updateAllowedHosts(for: manifests)
        let records = manifests.enumerated().map { index, manifest in
            WidgetRecord(manifest: manifest, position: index, lastLoadedAt: nil, lastError: nil)
        }
        bridge.bootstrapDashboard(records: records, isEditing: false)
    }

    func waitUntilReady() async throws {
        try await waitUntil { self.ready }
    }

    func waitUntilLoaded(id: UUID) async throws {
        try await waitUntil {
            self.loadedIDs.contains(id)
        }
    }

    func waitUntilLoadedCount(_ count: Int, for id: UUID) async throws {
        try await waitUntil {
            self.loadedIDs.filter { $0 == id }.count >= count
        }
    }

    func pageText() async throws -> String {
        let result = try await webView.evaluateJavaScript("document.body.innerText") as? String
        return result ?? ""
    }
}

private enum WidgetTestError: Error {
    case timedOut
}

private func waitUntil(
    timeout: TimeInterval = 2.0,
    interval: TimeInterval = 0.02,
    condition: @escaping @MainActor () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }
    throw WidgetTestError.timedOut
}

private final class MockWidgetURLProtocol: URLProtocol {
    static var requestCount = 0
    static var responseData = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCount += 1
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func textWidgetManifest(title: String, content: String, markdown: Bool = false) -> WidgetManifest {
    WidgetManifest(
        widgetType: .text,
        config: .text(TextConfig(title: title, markdown: markdown)),
        skillChain: [
            WidgetSkillStep(
                step: 1,
                skill: .transform,
                params: [
                    "data": AnyCodable(["content": content]),
                    "mapping": AnyCodable(["content": "content"]),
                ],
                outputKey: "textData"
            ),
        ],
        returns: "textData",
        ttl: 300,
        prompt: title
    )
}

private func fetchWidgetManifest(url: String) -> WidgetManifest {
    WidgetManifest(
        widgetType: .statCard,
        config: .statCard(
            StatCardConfig(
                title: "Price",
                valueField: "value",
                prefix: "$",
                suffix: nil,
                changeField: nil,
                changeIsPercent: nil
            )
        ),
        skillChain: [
            WidgetSkillStep(step: 1, skill: .fetchUrl, params: ["url": AnyCodable(url)], outputKey: "raw"),
            WidgetSkillStep(step: 2, skill: .parseJson, params: ["json": AnyCodable("$raw")], outputKey: "json"),
            WidgetSkillStep(
                step: 3,
                skill: .transform,
                params: [
                    "data": AnyCodable("$json"),
                    "mapping": AnyCodable(["value": "value"]),
                ],
                outputKey: "cardData"
            ),
        ],
        returns: "cardData",
        ttl: 300,
        prompt: "Price"
    )
}
