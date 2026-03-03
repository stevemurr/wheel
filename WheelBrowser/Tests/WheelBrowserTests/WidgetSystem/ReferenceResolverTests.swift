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

    // MARK: - Type Passthrough

    @Test("Numeric value passthrough (not string)")
    func numericPassthrough() throws {
        let params: [String: AnyCodable] = [
            "count": AnyCodable(42)
        ]
        let resolved = try ReferenceResolver.resolve(params: params, context: [:])
        #expect(resolved["count"] as? Int == 42)
    }

    @Test("Bool value passthrough")
    func boolPassthrough() throws {
        let params: [String: AnyCodable] = [
            "flag": AnyCodable(true)
        ]
        let resolved = try ReferenceResolver.resolve(params: params, context: [:])
        #expect(resolved["flag"] as? Bool == true)
    }

    @Test("Null value passthrough")
    func nullPassthrough() throws {
        let params: [String: AnyCodable] = [
            "empty": AnyCodable(NSNull())
        ]
        let resolved = try ReferenceResolver.resolve(params: params, context: [:])
        #expect(resolved["empty"] is NSNull)
    }

    @Test("Mixed text with multiple references in one string")
    func mixedTextMultipleRefs() throws {
        let params: [String: AnyCodable] = [
            "msg": AnyCodable("Hello {{a.output}}, welcome to {{b.output}}!")
        ]
        let context: [String: Any] = ["a": "World", "b": "Earth"]
        let resolved = try ReferenceResolver.resolve(params: params, context: context)
        #expect(resolved["msg"] as? String == "Hello World, welcome to Earth!")
    }

    @Test("Triple-nested dict resolution")
    func tripleNestedDict() throws {
        let params: [String: AnyCodable] = [
            "outer": AnyCodable([
                "mid": [
                    "inner": "{{step1.output}}"
                ] as [String: Any]
            ] as [String: Any])
        ]
        let context: [String: Any] = ["step1": "deep_value"]
        let resolved = try ReferenceResolver.resolve(params: params, context: context)
        let outer = resolved["outer"] as? [String: Any]
        let mid = outer?["mid"] as? [String: Any]
        #expect(mid?["inner"] as? String == "deep_value")
    }

    @Test("Array containing references")
    func arrayContainingRefs() throws {
        let params: [String: AnyCodable] = [
            "values": AnyCodable(["{{x.output}}", 42, "{{y.output}}"] as [Any])
        ]
        let context: [String: Any] = ["x": "alpha", "y": "beta"]
        let resolved = try ReferenceResolver.resolve(params: params, context: context)
        let values = resolved["values"] as? [Any]
        #expect(values?.count == 3)
        #expect(values?[0] as? String == "alpha")
        #expect(values?[1] as? Int == 42)
        #expect(values?[2] as? String == "beta")
    }
}
