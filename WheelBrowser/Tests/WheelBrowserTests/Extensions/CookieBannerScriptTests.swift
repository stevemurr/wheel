import Foundation
import Testing
import WebKit
@testable import WheelBrowser

@Suite("Cookie Banner Script Tests", .serialized)
@MainActor
struct CookieBannerScriptTests {
    @Test("Reject button is preferred over accept")
    func rejectButtonWins() async throws {
        let webView = try await makeWebViewWithCookieScript()

        try await loadHTML(
            """
            <html>
            <body>
              <div id="cookie-banner">
                <p>This site uses cookies to personalize content.</p>
                <button id="accept" onclick="window.__acceptCount = (window.__acceptCount || 0) + 1">Accept all</button>
                <button id="reject" onclick="window.__rejectCount = (window.__rejectCount || 0) + 1">Reject all</button>
              </div>
            </body>
            </html>
            """,
            baseURL: URL(string: "https://example.com")!,
            in: webView
        )

        try await waitUntil {
            let rejectCount = try await webView.evaluateJavaScript("window.__rejectCount || 0") as? Int
            return rejectCount == 1
        }

        let acceptCount = try await webView.evaluateJavaScript("window.__acceptCount || 0") as? Int
        let bannerDisplay = try await webView.evaluateJavaScript(
            "getComputedStyle(document.getElementById('cookie-banner')).display"
        ) as? String

        #expect(acceptCount == 0)
        #expect(bannerDisplay == "none")
    }

    @Test("Necessary-only controls are treated as reject actions")
    func necessaryOnlyCountsAsReject() async throws {
        let webView = try await makeWebViewWithCookieScript()

        try await loadHTML(
            """
            <html>
            <body>
              <div class="cookie-consent">
                <p>Manage cookie preferences and privacy choices.</p>
                <button id="necessary" onclick="window.__necessaryCount = (window.__necessaryCount || 0) + 1">Use only necessary cookies</button>
              </div>
            </body>
            </html>
            """,
            baseURL: URL(string: "https://example.com/preferences")!,
            in: webView
        )

        try await waitUntil {
            let necessaryCount = try await webView.evaluateJavaScript("window.__necessaryCount || 0") as? Int
            return necessaryCount == 1
        }
    }

    @Test("Generic continue buttons are not auto-clicked")
    func genericContinueIsIgnored() async throws {
        let webView = try await makeWebViewWithCookieScript()

        try await loadHTML(
            """
            <html>
            <body>
              <div id="cookie-banner">
                <p>Cookie preferences</p>
                <button id="continue" onclick="window.__continueCount = (window.__continueCount || 0) + 1">Continue</button>
              </div>
            </body>
            </html>
            """,
            baseURL: URL(string: "https://example.com/home")!,
            in: webView
        )

        try await Task.sleep(nanoseconds: 200_000_000)
        let continueCount = try await webView.evaluateJavaScript("window.__continueCount || 0") as? Int
        #expect(continueCount == 0)
    }

    private func makeWebViewWithCookieScript() async throws -> WKWebView {
        let originalExtensionsEnabled = AppSettings.shared.extensionsEnabled
        let originalAdBlockerEnabled = AppSettings.shared.adBlockerEnabled
        let originalAllowlistRaw = AppSettings.shared.adBlockDomainAllowlistRaw

        AppSettings.shared.extensionsEnabled = true
        AppSettings.shared.adBlockerEnabled = true
        AppSettings.shared.adBlockDomainAllowlistRaw = ""

        defer {
            AppSettings.shared.extensionsEnabled = originalExtensionsEnabled
            AppSettings.shared.adBlockerEnabled = originalAdBlockerEnabled
            AppSettings.shared.adBlockDomainAllowlistRaw = originalAllowlistRaw
        }

        let tempRoot = try ExtensionTestSupport.makeTemporaryDirectory()
        let bundledRoot = tempRoot.appendingPathComponent("bundled", isDirectory: true)
        let sideloadRoot = tempRoot.appendingPathComponent("sideloaded", isDirectory: true)
        try FileManager.default.createDirectory(at: bundledRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sideloadRoot, withIntermediateDirectories: true)

        let scriptContents = try String(contentsOf: cookieBannerScriptURL(), encoding: .utf8)
        try ExtensionTestSupport.makeLocalExtension(
            in: bundledRoot,
            folderName: "cookie-script",
            extensionID: "com.example.cookies",
            scriptContents: scriptContents,
            blockerContents: "! no blockers"
        )

        let blockerManager = ContentBlockerManager(
            stateFileURL: tempRoot.appendingPathComponent("filter_lists.json"),
            cacheDirectoryURL: tempRoot.appendingPathComponent("cache", isDirectory: true)
        )
        let registry = ExtensionRegistry(
            bundledExtensionsURL: bundledRoot,
            sideloadedExtensionsURL: sideloadRoot,
            stateFileURL: tempRoot.appendingPathComponent("extensions.json"),
            contentBlockerManager: blockerManager
        )

        await registry.reload()

        let factory = BrowserWebViewConfigurationFactory(registry: registry)
        return WKWebView(frame: .zero, configuration: factory.makeConfiguration(surface: .overlay))
    }

    private func cookieBannerScriptURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/WheelBrowser/Resources/Extensions/com.wheel.adblock/scripts/cookie-banners.js")
    }
}

private enum CookieBannerTestError: Error {
    case timedOut
}

@MainActor
private func waitUntil(
    timeout: TimeInterval = 2.0,
    interval: TimeInterval = 0.02,
    condition: @escaping @MainActor () async throws -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if try await condition() {
            return
        }
        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }
    throw CookieBannerTestError.timedOut
}
