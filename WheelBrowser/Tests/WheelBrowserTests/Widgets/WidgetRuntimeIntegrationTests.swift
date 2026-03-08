import Foundation
import Testing
import WebKit
@testable import WheelBrowser

@Suite("WidgetRuntimeIntegration", .serialized)
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
    @Test("Runtime renders local clock widgets")
    func rendersLocalClockWidget() async throws {
        let harness = try WidgetRuntimeHarness()
        harness.load()
        try await harness.waitUntilReady()

        let manifest = clockWidgetManifest(title: "UTC Clock", timeZone: "UTC")
        harness.bootstrap([manifest])
        try await harness.waitUntilLoaded(id: manifest.id)

        let rendered = try await harness.pageText()
        #expect(rendered.contains("UTC Clock"))
        #expect(rendered.contains("UTC"))
    }

    @MainActor
    @Test("Runtime gives clock widgets the dedicated clock presentation")
    func givesClockWidgetsDedicatedPresentation() async throws {
        let harness = try WidgetRuntimeHarness()
        harness.load()
        try await harness.waitUntilReady()

        let manifest = clockWidgetManifest(title: "UTC Clock", timeZone: "UTC")
        harness.bootstrap([manifest])
        try await harness.waitUntilLoaded(id: manifest.id)

        let presentation = try await harness.webView.evaluateJavaScript(
            "document.querySelector('[data-widget-id=\"\(manifest.id.uuidString)\"]')?.dataset.presentation"
        ) as? String
        let timeText = try await harness.webView.evaluateJavaScript(
            "document.querySelector('[data-widget-id=\"\(manifest.id.uuidString)\"] .clock-time-primary')?.textContent"
        ) as? String

        #expect(presentation == "clock")
        #expect((timeText ?? "").isEmpty == false)
    }

    @MainActor
    @Test("Clock widget content fits inside its panel")
    func clockWidgetFitsInsidePanel() async throws {
        let harness = try WidgetRuntimeHarness()
        harness.load()
        try await harness.waitUntilReady()

        let manifest = clockWidgetManifest(title: "UTC Clock", timeZone: "UTC")
        harness.bootstrap([manifest])
        try await harness.waitUntilLoaded(id: manifest.id)

        let fits = try await harness.webView.evaluateJavaScript(
            """
            (() => {
              const panel = document.querySelector('[data-widget-id="\(manifest.id.uuidString)"] .clock-panel');
              const date = document.querySelector('[data-widget-id="\(manifest.id.uuidString)"] .clock-date');
              const time = document.querySelector('[data-widget-id="\(manifest.id.uuidString)"] .clock-time');
              if (!panel || !date || !time) return false;
              const panelRect = panel.getBoundingClientRect();
              const dateRect = date.getBoundingClientRect();
              const timeRect = time.getBoundingClientRect();
              return timeRect.bottom <= panelRect.bottom - 16 && dateRect.bottom <= panelRect.bottom - 12;
            })()
            """
        ) as? Bool

        #expect(fits == true)
    }

    @MainActor
    @Test("Runtime updates clock widgets in real time")
    func updatesClockWidgetsInRealTime() async throws {
        let harness = try WidgetRuntimeHarness()
        harness.load()
        try await harness.waitUntilReady()

        let manifest = clockWidgetManifest(title: "UTC Clock", timeZone: "UTC")
        harness.bootstrap([manifest])
        try await harness.waitUntilLoaded(id: manifest.id)

        let selector = "[data-widget-id=\"\(manifest.id.uuidString)\"] .clock-time-primary"
        let firstValue = try await harness.webView.evaluateJavaScript(
            "document.querySelector('\(selector)')?.textContent"
        ) as? String

        try await Task.sleep(nanoseconds: 1_200_000_000)

        let secondValue = try await harness.webView.evaluateJavaScript(
            "document.querySelector('\(selector)')?.textContent"
        ) as? String

        #expect(firstValue != nil)
        #expect(secondValue != nil)
        #expect(firstValue != secondValue)
    }

    @MainActor
    @Test("Runtime renders multi-clock list widgets")
    func rendersMultiClockWidget() async throws {
        let harness = try WidgetRuntimeHarness()
        harness.load()
        try await harness.waitUntilReady()

        let manifest = multiClockWidgetManifest()
        harness.bootstrap([manifest])
        try await harness.waitUntilLoaded(id: manifest.id)

        let rendered = try await harness.pageText()
        #expect(rendered.contains("Pacific"))
        #expect(rendered.contains("Beijing"))
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
    @Test("Runtime emits remove actions and removes the card locally")
    func emitsRemoveActions() async throws {
        let harness = try WidgetRuntimeHarness()
        harness.load()
        try await harness.waitUntilReady()

        let manifest = textWidgetManifest(title: "Removable", content: "Delete me")
        harness.bridge.bootstrapDashboard(
            records: [WidgetRecord(manifest: manifest, position: 0, lastAttemptedAt: nil, lastLoadedAt: nil, lastError: nil)],
            isEditing: true
        )
        try await harness.waitUntilLoaded(id: manifest.id)

        _ = try await harness.webView.evaluateJavaScript(
            "document.querySelector('[data-widget-action=\"remove\"]')?.click(); true;"
        )

        try await waitUntil {
            harness.actions.contains(.remove(manifest.id))
        }

        let cardCount = try await harness.webView.evaluateJavaScript(
            "document.querySelectorAll('.widget-card').length"
        ) as? Int
        #expect(cardCount == 0)
    }

    @MainActor
    @Test("Runtime toggles widget width preferences while editing")
    func togglesWidgetWidthPreferences() async throws {
        let harness = try WidgetRuntimeHarness()
        harness.load()
        try await harness.waitUntilReady()

        let manifest = textWidgetManifest(title: "Wide", content: "Focus")
        harness.bridge.bootstrapDashboard(
            records: [WidgetRecord(manifest: manifest, position: 0, lastAttemptedAt: nil, lastLoadedAt: nil, lastError: nil)],
            isEditing: true
        )
        try await harness.waitUntilLoaded(id: manifest.id)

        _ = try await harness.webView.evaluateJavaScript(
            "document.querySelector('[data-widget-action=\"toggleLayout\"]')?.click(); true;"
        )

        try await waitUntil {
            harness.actions.contains(.toggleLayout(manifest.id))
        }

        let layout = try await harness.webView.evaluateJavaScript(
            "document.querySelector('[data-widget-id=\"\(manifest.id.uuidString)\"]')?.dataset.layoutPreference"
        ) as? String
        #expect(layout == "singleColumn")

        _ = try await harness.webView.evaluateJavaScript(
            "document.querySelector('[data-widget-action=\"toggleLayout\"]')?.click(); true;"
        )

        try await waitUntil {
            harness.actions.filter { $0 == .toggleLayout(manifest.id) }.count >= 2
        }

        let fullWidthLayout = try await harness.webView.evaluateJavaScript(
            "document.querySelector('[data-widget-id=\"\(manifest.id.uuidString)\"]')?.dataset.layoutPreference"
        ) as? String
        #expect(fullWidthLayout == "fullWidth")
    }

    @MainActor
    @Test("Runtime promotes a mixed three-widget dashboard into a hero layout")
    func promotesMixedThreeWidgetLayout() async throws {
        let harness = try WidgetRuntimeHarness()
        harness.load()
        try await harness.waitUntilReady()

        let compactLead = textWidgetManifest(title: "Quick Note", content: "Small card")
        let heroCandidate = textWidgetManifest(
            title: "Longform Brief",
            content: "A markdown card that should become the lead layout treatment.",
            markdown: true
        )
        let compactTail = textWidgetManifest(title: "Status", content: "Nominal")

        harness.bootstrap([compactLead, heroCandidate, compactTail])
        try await waitUntil {
            let heroTitle = try? await harness.webView.evaluateJavaScript(
                "document.querySelector('.widget-card--hero .widget-title')?.textContent"
            ) as? String
            return heroTitle == "Longform Brief"
        }

        let className = try await harness.webView.evaluateJavaScript(
            "document.getElementById('dashboard')?.className"
        ) as? String
        #expect(className?.contains("dashboard--count-3") == true)
        #expect(className?.contains("dashboard--mixed") == true)
    }

    @MainActor
    @Test("Runtime keeps explicitly single-column widgets out of the hero slot")
    func singleColumnWidgetsDoNotBecomeHero() async throws {
        let harness = try WidgetRuntimeHarness()
        harness.load()
        try await harness.waitUntilReady()

        let first = WidgetRecord(
            manifest: textWidgetManifest(
                title: "Longform Brief",
                content: "A markdown card that would normally become the hero treatment.",
                markdown: true
            ),
            position: 0,
            layoutPreference: .singleColumn,
            lastAttemptedAt: nil,
            lastLoadedAt: nil,
            lastError: nil
        )
        let second = WidgetRecord(
            manifest: textWidgetManifest(title: "Quick Note", content: "Small card"),
            position: 1,
            lastAttemptedAt: nil,
            lastLoadedAt: nil,
            lastError: nil
        )
        let third = WidgetRecord(
            manifest: textWidgetManifest(title: "Status", content: "Nominal"),
            position: 2,
            lastAttemptedAt: nil,
            lastLoadedAt: nil,
            lastError: nil
        )

        harness.bridge.bootstrapDashboard(records: [first, second, third], isEditing: false)
        try await harness.waitUntilLoaded(id: first.id)

        let heroTitle = try await harness.webView.evaluateJavaScript(
            "document.querySelector('.widget-card--hero .widget-title')?.textContent"
        ) as? String
        let firstPreference = try await harness.webView.evaluateJavaScript(
            "document.querySelector('[data-widget-id=\"\(first.id.uuidString)\"]')?.dataset.layoutPreference"
        ) as? String
        let firstHasHeroClass = try await harness.webView.evaluateJavaScript(
            "document.querySelector('[data-widget-id=\"\(first.id.uuidString)\"]')?.classList.contains('widget-card--hero')"
        ) as? Bool

        #expect(firstPreference == "singleColumn")
        #expect(firstHasHeroClass == false)
        #expect(heroTitle == nil)
    }

    @MainActor
    @Test("Runtime keeps three compact widgets in the compact layout")
    func keepsThreeCompactWidgetsCompact() async throws {
        let harness = try WidgetRuntimeHarness()
        harness.load()
        try await harness.waitUntilReady()

        harness.bootstrap([
            textWidgetManifest(title: "One", content: "First"),
            textWidgetManifest(title: "Two", content: "Second"),
            textWidgetManifest(title: "Three", content: "Third"),
        ])

        try await waitUntil {
            let className = try? await harness.webView.evaluateJavaScript(
                "document.getElementById('dashboard')?.className"
            ) as? String
            return className?.contains("dashboard--all-compact") == true
        }

        let heroCount = try await harness.webView.evaluateJavaScript(
            "document.querySelectorAll('.widget-card--hero').length"
        ) as? Int
        #expect(heroCount == 0)
    }

    @MainActor
    @Test("Runtime cache avoids repeated fetches within TTL")
    func cacheAvoidsRepeatedFetches() async throws {
        MockWidgetURLProtocol.requestCount = 0
        MockWidgetURLProtocol.responseData = Data(#"{"value":42}"#.utf8)
        MockWidgetURLProtocol.lastRequest = nil
        MockWidgetURLProtocol.lastBodyData = nil
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
            records: [WidgetRecord(manifest: manifest, position: 0, lastAttemptedAt: nil, lastLoadedAt: nil, lastError: nil)],
            isEditing: false
        )
        try await harness.waitUntilLoadedCount(2, for: manifest.id)

        #expect(MockWidgetURLProtocol.requestCount == 1)
    }

    @MainActor
    @Test("Runtime forwards fetch method headers and body")
    func forwardsFetchRequestDetails() async throws {
        MockWidgetURLProtocol.requestCount = 0
        MockWidgetURLProtocol.responseData = Data(#"{"ok":true}"#.utf8)
        MockWidgetURLProtocol.lastRequest = nil
        MockWidgetURLProtocol.lastBodyData = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockWidgetURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let harness = try WidgetRuntimeHarness(session: session)
        harness.load()
        try await harness.waitUntilReady()

        let manifest = postFetchWidgetManifest()
        harness.bootstrap([manifest])
        try await harness.waitUntilLoaded(id: manifest.id)

        guard let request = MockWidgetURLProtocol.lastRequest else {
            Issue.record("Expected proxied request to reach URLSession")
            return
        }

        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = String(data: MockWidgetURLProtocol.lastBodyData ?? Data(), encoding: .utf8)
        #expect(body == #"{"pair":"BTCUSD"}"#)
    }

    @MainActor
    @Test("Runtime escapes plain text widget content")
    func escapesPlainTextContent() async throws {
        let harness = try WidgetRuntimeHarness()
        harness.load()
        try await harness.waitUntilReady()

        let manifest = textWidgetManifest(title: "Escaped", content: "<b>literal</b>")
        harness.bootstrap([manifest])
        try await harness.waitUntilLoaded(id: manifest.id)

        let innerHTML = try await harness.webView.evaluateJavaScript(
            "document.querySelector('.text-block')?.innerHTML"
        ) as? String
        #expect(innerHTML == "&lt;b&gt;literal&lt;/b&gt;")
    }

    @MainActor
    @Test("Runtime renders chart legends and axis labels for line charts")
    func rendersLineChartMetadata() async throws {
        let harness = try WidgetRuntimeHarness()
        harness.load()
        try await harness.waitUntilReady()

        let manifest = lineChartWidgetManifest(title: "AMD Price (7D)")
        harness.bootstrap([manifest])
        try await harness.waitUntilLoaded(id: manifest.id)

        let legend = try await harness.webView.evaluateJavaScript(
            "document.querySelector('[data-widget-id=\"\(manifest.id.uuidString)\"] .chart-legend__label')?.textContent"
        ) as? String
        let axisLabelCount = try await harness.webView.evaluateJavaScript(
            "document.querySelectorAll('[data-widget-id=\"\(manifest.id.uuidString)\"] .chart-axis-labels span').length"
        ) as? Int

        #expect(legend == "AMD")
        #expect(axisLabelCount == 3)
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
              let html = try? WidgetRuntimeResources.inlineRuntimeHTML() else {
            Issue.record("Missing widget runtime resource")
            return
        }
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func bootstrap(_ manifests: [WidgetManifest]) {
        schemeHandler.updateAllowedHosts(for: manifests)
        let records = manifests.enumerated().map { index, manifest in
            WidgetRecord(manifest: manifest, position: index, lastAttemptedAt: nil, lastLoadedAt: nil, lastError: nil)
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
        let result = try await webView.evaluateJavaScript("document.getElementById('dashboard')?.textContent") as? String
        return result ?? ""
    }
}

private enum WidgetTestError: Error {
    case timedOut
}

private func waitUntil(
    timeout: TimeInterval = 2.0,
    interval: TimeInterval = 0.02,
    condition: @escaping @MainActor () async -> Bool
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
    static var lastRequest: URLRequest?
    static var lastBodyData: Data?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCount += 1
        Self.lastRequest = request
        Self.lastBodyData = request.httpBody ?? Self.readBody(from: request.httpBodyStream)
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

    private static func readBody(from stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }

        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var data = Data()
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count < 0 {
                return nil
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
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

private func clockWidgetManifest(title: String, timeZone: String) -> WidgetManifest {
    WidgetManifest(
        widgetType: .text,
        config: .text(TextConfig(title: title, markdown: false)),
        skillChain: [
            WidgetSkillStep(
                step: 1,
                skill: .currentDateTime,
                params: [
                    "timeZone": AnyCodable(timeZone),
                    "showTimeZone": AnyCodable(true),
                    "includeSeconds": AnyCodable(true),
                ],
                outputKey: "clock"
            ),
        ],
        returns: "clock",
        ttl: 0,
        prompt: title
    )
}

private func multiClockWidgetManifest() -> WidgetManifest {
    WidgetManifest(
        widgetType: .list,
        config: .list(
            ListConfig(
                title: "Pacific and Beijing",
                labelField: "label",
                valueField: "time",
                subtitleField: "timeZone",
                badgeField: nil,
                captionField: nil,
                iconField: nil,
                linkField: nil,
                maxItems: 2,
                variant: .compact
            )
        ),
        skillChain: [
            WidgetSkillStep(
                step: 1,
                skill: .currentDateTime,
                params: [
                    "timeZone": AnyCodable("America/Los_Angeles"),
                    "label": AnyCodable("Pacific"),
                    "showTimeZone": AnyCodable(true),
                    "includeSeconds": AnyCodable(true),
                ],
                outputKey: "pacificClock"
            ),
            WidgetSkillStep(
                step: 2,
                skill: .currentDateTime,
                params: [
                    "timeZone": AnyCodable("Asia/Shanghai"),
                    "label": AnyCodable("Beijing"),
                    "showTimeZone": AnyCodable(true),
                    "includeSeconds": AnyCodable(true),
                ],
                outputKey: "beijingClock"
            ),
            WidgetSkillStep(
                step: 3,
                skill: .transform,
                params: [
                    "data": AnyCodable(["$pacificClock", "$beijingClock"]),
                    "mapping": AnyCodable([
                        "label": "label",
                        "time": "formatted",
                    ]),
                ],
                outputKey: "clockList"
            ),
        ],
        returns: "clockList",
        ttl: 0,
        prompt: "Pacific and Beijing"
    )
}

private func postFetchWidgetManifest() -> WidgetManifest {
    WidgetManifest(
        widgetType: .text,
        config: .text(TextConfig(title: "POST", markdown: false)),
        skillChain: [
            WidgetSkillStep(
                step: 1,
                skill: .fetchUrl,
                params: [
                    "url": AnyCodable("https://api.example.com/query"),
                    "method": AnyCodable("POST"),
                    "headers": AnyCodable([
                        "Content-Type": "application/json",
                    ]),
                    "body": AnyCodable(#"{"pair":"BTCUSD"}"#),
                ],
                outputKey: "raw"
            ),
            WidgetSkillStep(
                step: 2,
                skill: .transform,
                params: [
                    "data": AnyCodable([
                        "content": "fetch complete",
                    ]),
                    "mapping": AnyCodable([
                        "content": "content",
                    ]),
                ],
                outputKey: "textData"
            ),
        ],
        returns: "textData",
        ttl: 0,
        prompt: "POST sample"
    )
}

private func lineChartWidgetManifest(title: String) -> WidgetManifest {
    WidgetManifest(
        widgetType: .lineChart,
        config: .lineChart(
            LineChartConfig(
                title: title,
                xField: "date",
                series: [
                    LineChartSeries(field: "close", label: "AMD", color: "#ff6b35"),
                ],
                yPrefix: "$",
                showPoints: false
            )
        ),
        skillChain: [
            WidgetSkillStep(
                step: 1,
                skill: .transform,
                params: [
                    "data": AnyCodable([
                        ["date": "3/1", "close": 146.3],
                        ["date": "3/3", "close": 149.1],
                        ["date": "3/5", "close": 151.8],
                        ["date": "3/7", "close": 150.6],
                    ]),
                    "mapping": AnyCodable([
                        "date": "date",
                        "close": "close",
                    ]),
                ],
                outputKey: "chartData"
            ),
        ],
        returns: "chartData",
        ttl: 0,
        prompt: title
    )
}
