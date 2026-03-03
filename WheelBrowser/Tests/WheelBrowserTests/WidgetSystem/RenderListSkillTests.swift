import Testing
import Foundation
@testable import WheelBrowser

@Suite("RenderListSkill")
struct RenderListSkillTests {
    let skill = RenderListSkill()

    @Test("Headline extraction from items")
    func headlineExtraction() async throws {
        let result = try await skill.execute(params: [
            "input": [["title": "Hello World"]] as [[String: Any]],
            "headline_field": "title",
        ])
        guard case .list(_, let items) = result as? RenderInput else {
            Issue.record("Expected list RenderInput")
            return
        }
        #expect(items.count == 1)
        #expect(items[0].headline == "Hello World")
    }

    @Test("Subheadline extraction")
    func subheadlineExtraction() async throws {
        let result = try await skill.execute(params: [
            "input": [["title": "Main", "author": "Alice"]] as [[String: Any]],
            "headline_field": "title",
            "subheadline_field": "author",
        ])
        guard case .list(_, let items) = result as? RenderInput else {
            Issue.record("Expected list RenderInput")
            return
        }
        #expect(items[0].subheadline == "Alice")
    }

    @Test("Badge extraction")
    func badgeExtraction() async throws {
        let result = try await skill.execute(params: [
            "input": [["title": "Post", "score": 42]] as [[String: Any]],
            "headline_field": "title",
            "badge_field": "score",
        ])
        guard case .list(_, let items) = result as? RenderInput else {
            Issue.record("Expected list RenderInput")
            return
        }
        #expect(items[0].badge != nil)
        #expect(items[0].badge?.text == "42")
    }

    @Test("Empty array input")
    func emptyArrayInput() async throws {
        let result = try await skill.execute(params: [
            "input": [] as [[String: Any]],
            "headline_field": "title",
        ])
        guard case .list(_, let items) = result as? RenderInput else {
            Issue.record("Expected list RenderInput")
            return
        }
        #expect(items.isEmpty)
    }

    @Test("Missing headline field falls back to empty string")
    func missingHeadlineFieldFallback() async throws {
        let result = try await skill.execute(params: [
            "input": [["other": "value"]] as [[String: Any]],
            "headline_field": "title",
        ])
        guard case .list(_, let items) = result as? RenderInput else {
            Issue.record("Expected list RenderInput")
            return
        }
        #expect(items[0].headline == "")
    }

    @Test("Large list with 100 items")
    func largeList() async throws {
        let input = (0..<100).map { ["title": "Item \($0)"] as [String: Any] }
        let result = try await skill.execute(params: [
            "input": input,
            "headline_field": "title",
        ])
        guard case .list(_, let items) = result as? RenderInput else {
            Issue.record("Expected list RenderInput")
            return
        }
        #expect(items.count == 100)
        #expect(items[0].headline == "Item 0")
        #expect(items[99].headline == "Item 99")
    }

    @Test("Items with all optional fields present")
    func allOptionalFieldsPresent() async throws {
        let result = try await skill.execute(params: [
            "input": [[
                "title": "Full Item",
                "subtitle": "More info",
                "tag": "hot",
                "url": "https://example.com",
            ]] as [[String: Any]],
            "headline_field": "title",
            "subheadline_field": "subtitle",
            "badge_field": "tag",
            "badge_color": "orange",
            "link_field": "url",
        ])
        guard case .list(_, let items) = result as? RenderInput else {
            Issue.record("Expected list RenderInput")
            return
        }
        #expect(items[0].headline == "Full Item")
        #expect(items[0].subheadline == "More info")
        #expect(items[0].badge?.text == "hot")
        #expect(items[0].badge?.color == .orange)
        #expect(items[0].link == "https://example.com")
    }

    @Test("Items with no optional fields")
    func noOptionalFields() async throws {
        let result = try await skill.execute(params: [
            "input": [["title": "Simple"]] as [[String: Any]],
            "headline_field": "title",
        ])
        guard case .list(_, let items) = result as? RenderInput else {
            Issue.record("Expected list RenderInput")
            return
        }
        #expect(items[0].subheadline == nil)
        #expect(items[0].badge == nil)
        #expect(items[0].link == nil)
    }
}
