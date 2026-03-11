import Foundation
import Testing
@testable import WheelBrowser

@Suite("BrowserWebView")
struct BrowserWebViewTests {
    @Test("Hard reload cache purge only applies to HTTP pages")
    func supportsCachePurgingForHTTPOnly() {
        #expect(BrowserWebView.supportsCachePurgingHardReload(for: URL(string: "https://example.com")!) == true)
        #expect(BrowserWebView.supportsCachePurgingHardReload(for: URL(string: "http://example.com")!) == true)
        #expect(BrowserWebView.supportsCachePurgingHardReload(for: URL(fileURLWithPath: "/tmp/index.html")) == false)
        #expect(BrowserWebView.supportsCachePurgingHardReload(for: URL(string: "about:blank")!) == false)
    }

    @Test("Hard reload host matching accepts exact and subdomain cache records")
    func matchesHardReloadHosts() {
        #expect(BrowserWebView.matchesHardReloadHost("example.com", host: "example.com") == true)
        #expect(BrowserWebView.matchesHardReloadHost("example.com", host: "www.example.com") == true)
        #expect(BrowserWebView.matchesHardReloadHost("www.example.com", host: "example.com") == true)
        #expect(BrowserWebView.matchesHardReloadHost("api.other.com", host: "example.com") == false)
        #expect(BrowserWebView.matchesHardReloadHost("com", host: "example.com") == false)
    }
}
