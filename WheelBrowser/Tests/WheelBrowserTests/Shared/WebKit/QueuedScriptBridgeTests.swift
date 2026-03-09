import Foundation
import Testing
import WebKit
@testable import WheelBrowser

@Suite("QueuedScriptBridge")
@MainActor
struct QueuedScriptBridgeTests {
    @Test("Queued commands flush after ready and later sends bypass the queue")
    func queuedCommandsFlushAfterReady() {
        let bridge = TestQueuedBridge()
        let webView = RecordingWebView(configuration: WKWebViewConfiguration())

        bridge.attach(to: webView)
        bridge.sendCommand("bootstrap", payload: ["message": "hello"])

        #expect(webView.evaluatedScripts.isEmpty)

        bridge.handleMessage(["type": "ready"])

        #expect(bridge.readyCount == 1)
        #expect(webView.evaluatedScripts.count == 1)
        #expect(webView.evaluatedScripts[0].contains("receiveCommand('bootstrap'"))

        bridge.sendCommand("refresh", payload: ["count": 2])

        #expect(webView.evaluatedScripts.count == 2)
        #expect(webView.evaluatedScripts[1].contains("receiveCommand('refresh'"))
    }

    @Test("Detach clears pending commands and resets ready state")
    func detachClearsPendingCommandsAndReadyState() {
        let bridge = TestQueuedBridge()
        let firstWebView = RecordingWebView(configuration: WKWebViewConfiguration())
        let secondWebView = RecordingWebView(configuration: WKWebViewConfiguration())

        bridge.attach(to: firstWebView)
        bridge.sendCommand("bootstrap", payload: ["message": "queued"])
        bridge.detach()
        bridge.attach(to: secondWebView)
        bridge.handleMessage(["type": "ready"])

        #expect(secondWebView.evaluatedScripts.isEmpty)

        bridge.sendCommand("refresh", payload: ["count": 1])

        #expect(secondWebView.evaluatedScripts.count == 1)
        #expect(secondWebView.evaluatedScripts[0].contains("receiveCommand('refresh'"))
    }

    @Test("Hosted web view host applies request loads and teardown hooks")
    func hostedWebViewBuildsRequestLoads() throws {
        let requestURL = try #require(URL(string: "https://example.com/request"))
        var configuredWebView: RecordingWebView?
        var didConfigure = false
        var didTeardown = false
        let handler = TestScriptMessageHandler()
        let customConfiguration = WKWebViewConfiguration()
        let spec = HostedWKWebViewSpec(
            dataStorePolicy: .nonPersistent,
            scriptMessageHandlers: [
                .init(name: "bridge", handler: handler),
            ],
            makeConfiguration: {
                customConfiguration
            },
            makeWebView: { configuration in
                #expect(configuration === customConfiguration)
                let webView = RecordingWebView(configuration: configuration)
                configuredWebView = webView
                return webView
            },
            configure: { _ in
                didConfigure = true
            },
            initialLoad: .request(URLRequest(url: requestURL)),
            teardown: { _ in
                didTeardown = true
            }
        )

        let builtWebView = WKWebViewHost.build(spec: spec)
        let recordingWebView = try #require(configuredWebView)

        #expect(builtWebView === recordingWebView)
        #expect(didConfigure)
        #expect(recordingWebView.lastRequest?.url == requestURL)

        WKWebViewHost.dismantle(builtWebView, spec: spec)

        #expect(didTeardown)
    }

    @Test("Hosted web view host can attach and dismantle an existing web view")
    func hostedWebViewAttachesExistingViews() throws {
        let requestURL = try #require(URL(string: "https://example.com/existing"))
        let existingWebView = RecordingWebView(configuration: WKWebViewConfiguration())
        var didConfigure = false
        var didTeardown = false
        let spec = HostedWKWebViewSpec(
            scriptMessageHandlers: [
                .init(name: "bridge", handler: TestScriptMessageHandler()),
            ],
            configure: { _ in
                didConfigure = true
            },
            initialLoad: .request(URLRequest(url: requestURL)),
            teardown: { _ in
                didTeardown = true
            }
        )

        WKWebViewHost.attach(existingWebView, spec: spec)

        #expect(didConfigure)
        #expect(existingWebView.lastRequest?.url == requestURL)

        WKWebViewHost.dismantle(existingWebView, spec: spec)

        #expect(didTeardown)
    }

    @Test("Hosted web view host supports HTML and file loads")
    func hostedWebViewSupportsHTMLAndFileLoads() throws {
        let htmlBaseURL = try #require(URL(string: "https://example.com/base"))
        var htmlWebView: RecordingWebView?
        let htmlSpec = HostedWKWebViewSpec(
            makeWebView: { configuration in
                let webView = RecordingWebView(configuration: configuration)
                htmlWebView = webView
                return webView
            },
            initialLoad: .htmlString("<html>Hi</html>", baseURL: htmlBaseURL)
        )

        _ = WKWebViewHost.build(spec: htmlSpec)

        let builtHTMLWebView = try #require(htmlWebView)
        #expect(builtHTMLWebView.lastHTML?.string == "<html>Hi</html>")
        #expect(builtHTMLWebView.lastHTML?.baseURL == htmlBaseURL)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("html")
        let readAccessURL = fileURL.deletingLastPathComponent()
        try Data("<html>File</html>".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var fileWebView: RecordingWebView?
        let fileSpec = HostedWKWebViewSpec(
            makeWebView: { configuration in
                let webView = RecordingWebView(configuration: configuration)
                fileWebView = webView
                return webView
            },
            initialLoad: .fileURL(fileURL, allowingReadAccessTo: readAccessURL)
        )

        _ = WKWebViewHost.build(spec: fileSpec)

        let builtFileWebView = try #require(fileWebView)
        #expect(builtFileWebView.lastFileLoad?.fileURL == fileURL)
        #expect(builtFileWebView.lastFileLoad?.readAccessURL == readAccessURL)
    }
}

@MainActor
private final class TestQueuedBridge: QueuedScriptBridge {
    var readyCount = 0

    init() {
        super.init(messageHandlerName: "testBridge", javaScriptReceiver: "TestReceiver")
    }

    override func bridgeDidBecomeReady() {
        readyCount += 1
    }
}

private final class TestScriptMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {}
}

@MainActor
private final class RecordingWebView: WKWebView {
    struct HTMLLoad {
        let string: String
        let baseURL: URL?
    }

    struct FileLoad {
        let fileURL: URL
        let readAccessURL: URL
    }

    var evaluatedScripts: [String] = []
    var lastRequest: URLRequest?
    var lastHTML: HTMLLoad?
    var lastFileLoad: FileLoad?

    init(configuration: WKWebViewConfiguration) {
        super.init(frame: .zero, configuration: configuration)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func evaluateJavaScript(
        _ javaScriptString: String,
        completionHandler: (@MainActor @Sendable (Any?, (any Error)?) -> Void)? = nil
    ) {
        evaluatedScripts.append(javaScriptString)
        completionHandler?(nil, nil)
    }

    override func load(_ request: URLRequest) -> WKNavigation? {
        lastRequest = request
        return nil
    }

    override func loadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation? {
        lastHTML = HTMLLoad(string: string, baseURL: baseURL)
        return nil
    }

    override func loadFileURL(_ URL: URL, allowingReadAccessTo readAccessURL: URL) -> WKNavigation? {
        lastFileLoad = FileLoad(fileURL: URL, readAccessURL: readAccessURL)
        return nil
    }
}
