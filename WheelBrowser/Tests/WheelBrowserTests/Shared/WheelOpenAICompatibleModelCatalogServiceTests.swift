import Foundation
import Testing
@testable import WheelBrowser

@Suite("WheelOpenAICompatibleModelCatalogService", .serialized)
struct WheelOpenAICompatibleModelCatalogServiceTests {
    @Test("OpenAI-compatible providers load /v1/models and send authorization when available")
    func fetchesModelsFromRootBaseURL() async throws {
        let service = makeService()

        MockModelCatalogURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "http://localhost:4000/v1/models")
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")

            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = Data(
                #"{"data":[{"id":"gpt-4.1-mini"},{"id":"gpt-4.1-mini"},{"id":"gpt-4.1"}]}"#.utf8
            )
            return (response, data)
        }

        let modelIDs = try await service.fetchModelIDs(
            for: .openAI,
            baseURL: "http://localhost:4000",
            apiKey: "secret"
        )

        #expect(modelIDs == ["gpt-4.1-mini", "gpt-4.1"])
    }

    @Test("Existing /v1 base URLs are reused for model discovery")
    func fetchesModelsFromV1BaseURL() async throws {
        let service = makeService()

        MockModelCatalogURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "http://localhost:8000/v1/models")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)

            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = Data(
                #"{"data":[{"id":"meta-llama/Llama-3.2-3B-Instruct"}]}"#.utf8
            )
            return (response, data)
        }

        let modelIDs = try await service.fetchModelIDs(
            for: .vllm,
            baseURL: "http://localhost:8000/v1",
            apiKey: nil
        )

        #expect(modelIDs == ["meta-llama/Llama-3.2-3B-Instruct"])
    }
}

private func makeService() -> WheelOpenAICompatibleModelCatalogService {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockModelCatalogURLProtocol.self]
    return WheelOpenAICompatibleModelCatalogService(
        session: URLSession(configuration: configuration)
    )
}

private final class MockModelCatalogURLProtocol: URLProtocol {
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
