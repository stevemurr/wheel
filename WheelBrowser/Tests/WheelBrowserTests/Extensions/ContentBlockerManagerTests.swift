import Foundation
import Testing
@testable import WheelBrowser

@Suite("ContentBlockerManager Tests", .serialized)
@MainActor
struct ContentBlockerManagerTests {
    @Test("Refresh stores remote metadata and cache fallback still compiles after failures")
    func refreshAndCacheFallback() async throws {
        AppSettings.shared.adBlockerEnabled = true

        let tempRoot = try ExtensionTestSupport.makeTemporaryDirectory()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let manager = ContentBlockerManager(
            session: session,
            stateFileURL: tempRoot.appendingPathComponent("filter_lists.json"),
            cacheDirectoryURL: tempRoot.appendingPathComponent("cache", isDirectory: true)
        )

        let remoteExtension = ExtensionTestSupport.makeRemoteExtension(
            extensionID: "com.example.remote",
            remoteURL: "https://example.com/list.txt"
        )

        manager.synchronize(with: [remoteExtension])

        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "ETag": "\"abc123\"",
                    "Last-Modified": "Wed, 21 Oct 2015 07:28:00 GMT"
                ]
            )!
            return (response, Data("||ads.example.com^".utf8))
        }

        await manager.refresh(force: false)

        let subscriptionAfterRefresh = try #require(manager.subscriptions.first)
        #expect(subscriptionAfterRefresh.checksum != nil)
        #expect(subscriptionAfterRefresh.lastSuccessAt != nil)
        #expect(subscriptionAfterRefresh.lastError == nil)

        MockURLProtocol.handler = { _ in
            throw URLError(.cannotFindHost)
        }

        await manager.refresh(force: true)
        #expect(manager.lastRefreshError != nil)

        let compiled = await manager.compileActiveRules(for: [remoteExtension])
        #expect(!(compiled.ruleListsByExtensionID["com.example.remote"]?.isEmpty ?? true))
    }

    @Test("Conditional 304 refresh keeps cached subscription healthy")
    func conditionalRefresh304() async throws {
        let tempRoot = try ExtensionTestSupport.makeTemporaryDirectory()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let manager = ContentBlockerManager(
            session: session,
            stateFileURL: tempRoot.appendingPathComponent("filter_lists.json"),
            cacheDirectoryURL: tempRoot.appendingPathComponent("cache", isDirectory: true)
        )

        let remoteExtension = ExtensionTestSupport.makeRemoteExtension(
            extensionID: "com.example.remote304",
            remoteURL: "https://example.com/list.txt"
        )

        manager.synchronize(with: [remoteExtension])

        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["ETag": "\"etag\""]
            )!
            return (response, Data("||ads.example.com^".utf8))
        }
        await manager.refresh(force: false)

        let lastSuccess = manager.subscriptions.first?.lastSuccessAt

        MockURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"etag\"")
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 304,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        await manager.refresh(force: false)

        #expect(manager.subscriptions.first?.lastSuccessAt != nil)
        #expect(manager.subscriptions.first?.lastSuccessAt != lastSuccess)
        #expect(manager.subscriptions.first?.lastError == nil)
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
