import Testing
import Foundation
@testable import WheelBrowser

@Suite("AnyCodable")
struct AnyCodableTests {

    @Test("Encode and decode Bool")
    func boolRoundTrip() throws {
        let value = AnyCodable(true)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        #expect(decoded.boolValue == true)
    }

    @Test("Encode and decode Int")
    func intRoundTrip() throws {
        let value = AnyCodable(42)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        #expect(decoded.intValue == 42)
    }

    @Test("Encode and decode Double")
    func doubleRoundTrip() throws {
        let value = AnyCodable(3.14)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        #expect(decoded.doubleValue == 3.14)
    }

    @Test("Encode and decode String")
    func stringRoundTrip() throws {
        let value = AnyCodable("hello")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        #expect(decoded.stringValue == "hello")
    }

    @Test("Encode and decode null")
    func nullRoundTrip() throws {
        let value = AnyCodable(NSNull())
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        #expect(decoded.isNull)
    }

    @Test("Encode and decode nested array")
    func arrayRoundTrip() throws {
        let value = AnyCodable([1, "two", 3.0] as [Any])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        let array = decoded.arrayValue
        #expect(array != nil)
        #expect(array?.count == 3)
    }

    @Test("Encode and decode nested dictionary")
    func dictRoundTrip() throws {
        let value = AnyCodable(["name": "test", "count": 5] as [String: Any])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        let dict = decoded.dictionaryValue
        #expect(dict != nil)
        #expect(dict?["name"] as? String == "test")
        #expect(dict?["count"] as? Int == 5)
    }

    @Test("Deeply nested structure")
    func deeplyNested() throws {
        let value = AnyCodable([
            "level1": [
                "level2": [
                    "value": 42
                ] as [String: Any]
            ] as [String: Any]
        ] as [String: Any])

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        let dict = decoded.dictionaryValue
        let level1 = dict?["level1"] as? [String: Any]
        let level2 = level1?["level2"] as? [String: Any]
        #expect(level2?["value"] as? Int == 42)
    }

    @Test("Convenience accessors return nil for wrong type")
    func wrongTypeAccessors() {
        let value = AnyCodable("hello")
        #expect(value.intValue == nil)
        #expect(value.doubleValue == nil)
        #expect(value.boolValue == nil)
        #expect(value.arrayValue == nil)
        #expect(value.dictionaryValue == nil)
        #expect(!value.isNull)
    }

    // MARK: - Additional Round-Trip Tests

    @Test("Empty string round-trip")
    func emptyStringRoundTrip() throws {
        let value = AnyCodable("")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        #expect(decoded.stringValue == "")
    }

    @Test("Empty array round-trip")
    func emptyArrayRoundTrip() throws {
        let value = AnyCodable([] as [Any])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        let array = decoded.arrayValue
        #expect(array != nil)
        #expect(array?.isEmpty == true)
    }

    @Test("Empty dict round-trip")
    func emptyDictRoundTrip() throws {
        let value = AnyCodable([:] as [String: Any])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        let dict = decoded.dictionaryValue
        #expect(dict != nil)
        #expect(dict?.isEmpty == true)
    }

    @Test("Date value handling as string")
    func dateValueHandling() throws {
        // Dates are not natively supported by AnyCodable, so they encode as strings
        let dateString = "2026-03-03T12:00:00Z"
        let value = AnyCodable(dateString)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        #expect(decoded.stringValue == dateString)
    }
}
