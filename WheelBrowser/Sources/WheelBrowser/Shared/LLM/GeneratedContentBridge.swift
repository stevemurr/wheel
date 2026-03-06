import Foundation
import FoundationModels

enum GeneratedContentBridgeError: LocalizedError {
    case expectedStructure
    case expectedArray
    case expectedDictionaryArray

    var errorDescription: String? {
        switch self {
        case .expectedStructure:
            return "Expected a structured object from generated content"
        case .expectedArray:
            return "Expected an array from generated content"
        case .expectedDictionaryArray:
            return "Expected an array of objects from generated content"
        }
    }
}

enum GeneratedContentBridge {
    static func prettyJSONString(from value: some ConvertibleToGeneratedContent) -> String? {
        let object = any(from: GeneratedContent(value))
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    static func any(from content: GeneratedContent) -> Any {
        switch content.kind {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .number(let value):
            return value.rounded() == value ? Int(value) : value
        case .string(let value):
            return value
        case .array(let elements):
            return elements.map(any(from:))
        case .structure(let properties, _):
            return properties.mapValues(any(from:))
        @unknown default:
            return NSNull()
        }
    }

    static func anyCodableDictionary(from content: GeneratedContent) throws -> [String: AnyCodable] {
        try dictionary(from: content).mapValues(AnyCodable.init)
    }

    static func dictionary(from content: GeneratedContent) throws -> [String: Any] {
        guard case .structure(let properties, _) = content.kind else {
            throw GeneratedContentBridgeError.expectedStructure
        }

        return properties.mapValues(any(from:))
    }

    static func dictionaryArray(from content: GeneratedContent?) throws -> [[String: Any]]? {
        guard let content else { return nil }
        guard case .array(let elements) = content.kind else {
            throw GeneratedContentBridgeError.expectedArray
        }

        return try elements.map { element in
            guard case .structure = element.kind else {
                throw GeneratedContentBridgeError.expectedDictionaryArray
            }
            return try dictionary(from: element)
        }
    }
}
