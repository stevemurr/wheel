import Testing
import Foundation
@testable import WheelBrowser

@Suite("FetchRestApiSkill")
struct FetchRestApiSkillTests {
    let skill = FetchRestApiSkill()

    @Test("Missing URL throws error")
    func missingUrl() async throws {
        await #expect(throws: WidgetError.self) {
            _ = try await skill.execute(params: [:])
        }
    }

    @Test("Empty URL string throws error")
    func emptyUrl() async throws {
        await #expect(throws: WidgetError.self) {
            _ = try await skill.execute(params: ["url": ""])
        }
    }

    @Test("Non-HTTPS URL throws error")
    func nonHttpsUrl() async throws {
        await #expect(throws: WidgetError.self) {
            _ = try await skill.execute(params: ["url": "http://api.github.com/repos"])
        }
    }

    @Test("Disallowed domain throws error")
    func disallowedDomain() async throws {
        await #expect(throws: WidgetError.self) {
            _ = try await skill.execute(params: ["url": "https://evil.example.com/data"])
        }
    }

    @Test("Invalid URL format throws error")
    func invalidUrlFormat() async throws {
        await #expect(throws: WidgetError.self) {
            _ = try await skill.execute(params: ["url": "not a url at all"])
        }
    }

    @Test("Allowed domains list is non-empty")
    func allowedDomainsNonEmpty() {
        #expect(!FetchRestApiSkill.allowedDomains.isEmpty)
        #expect(FetchRestApiSkill.allowedDomains.contains("api.github.com"))
        #expect(FetchRestApiSkill.allowedDomains.contains("api.coingecko.com"))
    }
}
