import Foundation
import Testing
import WebKit
@testable import WheelBrowser

enum ExtractionFixture {
    static func html(named name: String) throws -> String {
        let url = try fileURL(named: name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func url(named name: String) -> URL {
        URL(string: "https://example.com/\(name).html")!
    }

    static func fileURL(named name: String) throws -> URL {
        try #require(
            Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "ExtractionFixtures")
        )
    }
}

@MainActor
final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func waitForLoad() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

@MainActor
func loadHTML(_ html: String, baseURL: URL, in webView: WKWebView) async throws {
    let waiter = NavigationWaiter()
    webView.navigationDelegate = waiter
    async let loaded: Void = waiter.waitForLoad()
    webView.loadHTMLString(html, baseURL: baseURL)
    try await loaded
}

@MainActor
func loadFixture(named name: String, in webView: WKWebView) async throws -> URL {
    let fileURL = try ExtractionFixture.fileURL(named: name)
    try await awaitNavigation(in: webView) {
        webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
    }
    return fileURL
}

@MainActor
func reload(_ webView: WKWebView) async throws {
    try await awaitNavigation(in: webView) {
        webView.reload()
    }
}

@MainActor
func awaitNavigation(in webView: WKWebView, action: () -> Void) async throws {
    let waiter = NavigationWaiter()
    webView.navigationDelegate = waiter
    async let loaded: Void = waiter.waitForLoad()
    action()
    try await loaded
}

@MainActor
func waitUntilJavaScript(
    in webView: WKWebView,
    script: String,
    timeout: TimeInterval = 2.0,
    interval: TimeInterval = 0.02
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let matched = try await webView.evaluateJavaScript(script) as? Bool, matched {
            return
        }
        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }
    throw CocoaError(.userCancelled)
}

@MainActor
final class ReaderModeBindingState {
    var isLoading = false
    var isReaderMode = false
}
