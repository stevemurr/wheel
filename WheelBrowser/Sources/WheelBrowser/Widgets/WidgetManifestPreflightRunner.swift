import Foundation
import WebKit

enum WidgetManifestPreflightError: LocalizedError, Equatable {
    case missingRuntimeResources
    case runtimeStartupTimedOut
    case widgetExecutionTimedOut(UUID)
    case runtimeFailed(String)
    case widgetFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingRuntimeResources:
            return "Widget runtime resources are missing from the app bundle."
        case .runtimeStartupTimedOut:
            return "The hidden widget runtime did not start in time."
        case .widgetExecutionTimedOut:
            return "The widget did not finish rendering during preflight."
        case .runtimeFailed(let message):
            return "The hidden widget runtime failed: \(message)"
        case .widgetFailed(let message):
            return message
        }
    }
}

struct WidgetManifestPreflightRunner: Sendable {
    static let shared = WidgetManifestPreflightRunner()

    let session: URLSession
    let readyTimeout: Duration
    let executionTimeout: Duration

    init(
        session: URLSession = .shared,
        readyTimeout: Duration = .seconds(2),
        executionTimeout: Duration = .seconds(10)
    ) {
        self.session = session
        self.readyTimeout = readyTimeout
        self.executionTimeout = executionTimeout
    }

    @MainActor
    func preflight(_ manifest: WidgetManifest) async throws {
        let session = WidgetManifestPreflightSession(manifest: manifest, urlSession: session)
        defer { session.invalidate() }
        try await session.run(readyTimeout: readyTimeout, executionTimeout: executionTimeout)
    }
}

@MainActor
private final class WidgetManifestPreflightSession {
    private let manifest: WidgetManifest
    private let bridge = WidgetRuntimeBridge()
    private let schemeHandler: WidgetFetchSchemeHandler
    private let webView: WKWebView
    private var isReady = false
    private var didLoadWidget = false
    private var widgetErrorMessage: String?
    private var runtimeErrorMessage: String?

    init(manifest: WidgetManifest, urlSession: URLSession) {
        self.manifest = manifest
        schemeHandler = WidgetFetchSchemeHandler(session: urlSession)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: "widget-fetch")
        configuration.userContentController.add(bridge, name: "widgetBridge")

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        bridge.attach(to: webView)

        bridge.onReady = { [weak self] in
            self?.isReady = true
        }
        bridge.onWidgetLoaded = { [weak self] id in
            guard let self, id == self.manifest.id else { return }
            self.didLoadWidget = true
        }
        bridge.onWidgetError = { [weak self] id, message in
            guard let self, id == self.manifest.id else { return }
            self.widgetErrorMessage = message
        }
        bridge.onRuntimeError = { [weak self] message in
            self?.runtimeErrorMessage = message
        }
    }

    func run(readyTimeout: Duration, executionTimeout: Duration) async throws {
        guard let baseURL = WidgetRuntimeResources.runtimeDirectoryURL(),
              let html = try? WidgetRuntimeResources.inlineRuntimeHTML() else {
            throw WidgetManifestPreflightError.missingRuntimeResources
        }

        webView.loadHTMLString(html, baseURL: baseURL)

        try await waitUntil(timeout: readyTimeout, failure: .runtimeStartupTimedOut) { [self] in
            self.isReady || self.runtimeErrorMessage != nil
        }

        if let runtimeErrorMessage {
            throw WidgetManifestPreflightError.runtimeFailed(runtimeErrorMessage)
        }

        schemeHandler.updateAllowedHosts(for: [manifest])
        bridge.bootstrapDashboard(
            records: [
                WidgetRecord(
                    manifest: manifest,
                    position: 0,
                    lastAttemptedAt: nil,
                    lastLoadedAt: nil,
                    lastError: nil
                ),
            ],
            isEditing: false
        )

        try await waitUntil(timeout: executionTimeout, failure: .widgetExecutionTimedOut(manifest.id)) { [self] in
            self.didLoadWidget || self.widgetErrorMessage != nil || self.runtimeErrorMessage != nil
        }

        if let runtimeErrorMessage {
            throw WidgetManifestPreflightError.runtimeFailed(runtimeErrorMessage)
        }

        if let widgetErrorMessage {
            throw WidgetManifestPreflightError.widgetFailed(widgetErrorMessage)
        }

        if !didLoadWidget {
            throw WidgetManifestPreflightError.widgetExecutionTimedOut(manifest.id)
        }
    }

    func invalidate() {
        bridge.detach()
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "widgetBridge")
    }

    private func waitUntil(
        timeout: Duration,
        failure: WidgetManifestPreflightError,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while clock.now < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        throw failure
    }
}
