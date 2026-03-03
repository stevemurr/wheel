import Testing
import Foundation
@testable import WheelBrowser

@Suite("BFFClient")
struct BFFClientTests {

    @Test("Not configured when no base URL")
    func notConfigured() async {
        let client = BFFClient(baseURL: nil)
        let isConfigured = await client.isConfigured
        #expect(!isConfigured)
    }

    @Test("Configured when base URL provided")
    func configured() async {
        let client = BFFClient(baseURL: URL(string: "https://localhost:8080")!)
        let isConfigured = await client.isConfigured
        #expect(isConfigured)
    }
}
