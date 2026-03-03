import Testing
import Foundation
@testable import WheelBrowser

@Suite("ReferenceResolver")
struct ReferenceResolverTests {

    @Test("Resolve single full reference preserves type")
    func singleFullReference() throws {
        let params: [String: AnyCodable] = [
            "input": AnyCodable("{{fetch.output}}")
        ]
        let context: [String: Any] = [
            "fetch": [["title": "Hello"]]
        ]

        let resolved = try ReferenceResolver.resolve(params: params, context: context)
        let input = resolved["input"] as? [[String: Any]]
        #expect(input?.first?["title"] as? String == "Hello")
    }

    @Test("Resolve string interpolation with multiple refs")
    func stringInterpolation() throws {
        let params: [String: AnyCodable] = [
            "url": AnyCodable("https://api.example.com/{{base.output}}/data?key={{key.output}}")
        ]
        let context: [String: Any] = [
            "base": "users",
            "key": "abc123",
        ]

        let resolved = try ReferenceResolver.resolve(params: params, context: context)
        #expect(resolved["url"] as? String == "https://api.example.com/users/data?key=abc123")
    }

    @Test("No references passthrough unchanged")
    func noReferences() throws {
        let params: [String: AnyCodable] = [
            "subreddit": AnyCodable("swift"),
            "limit": AnyCodable(10),
        ]

        let resolved = try ReferenceResolver.resolve(params: params, context: [:])
        #expect(resolved["subreddit"] as? String == "swift")
        #expect(resolved["limit"] as? Int == 10)
    }

    @Test("Missing reference throws error")
    func missingReference() {
        let params: [String: AnyCodable] = [
            "input": AnyCodable("{{nonexistent.output}}")
        ]

        #expect(throws: WidgetError.self) {
            _ = try ReferenceResolver.resolve(params: params, context: [:])
        }
    }

    @Test("Nested dict references resolved")
    func nestedDictReferences() throws {
        let params: [String: AnyCodable] = [
            "config": AnyCodable(["inner": "{{step1.output}}"] as [String: Any])
        ]
        let context: [String: Any] = ["step1": "resolved_value"]

        let resolved = try ReferenceResolver.resolve(params: params, context: context)
        let config = resolved["config"] as? [String: Any]
        #expect(config?["inner"] as? String == "resolved_value")
    }

    @Test("Array references resolved")
    func arrayReferences() throws {
        let params: [String: AnyCodable] = [
            "items": AnyCodable(["{{a.output}}", "static", "{{b.output}}"] as [Any])
        ]
        let context: [String: Any] = ["a": "first", "b": "third"]

        let resolved = try ReferenceResolver.resolve(params: params, context: context)
        let items = resolved["items"] as? [Any]
        #expect(items?.count == 3)
        #expect(items?[0] as? String == "first")
        #expect(items?[1] as? String == "static")
        #expect(items?[2] as? String == "third")
    }
}
