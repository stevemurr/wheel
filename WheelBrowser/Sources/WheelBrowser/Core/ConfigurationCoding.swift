import Foundation

/// Protocol for types that can be configured with a dictionary of values.
///
/// This provides a type-safe way to serialize and deserialize configuration
/// data for widgets, agents, and other configurable components.
protocol ConfigurationCodable {
    /// Encodes the current configuration to a dictionary
    func encodeConfiguration() -> [String: Any]

    /// Decodes configuration from a dictionary
    mutating func decodeConfiguration(_ data: [String: Any])
}

/// Namespace for configuration coding utilities
enum ConfigurationCoding {
    /// Encodes a Codable value to a dictionary representation
    ///
    /// - Parameter value: The Codable value to encode
    /// - Returns: Dictionary representation, or nil if encoding fails
    static func encode<T: Encodable>(_ value: T) -> [String: Any]? {
        do {
            let data = try JSONEncoder().encode(value)
            let json = try JSONSerialization.jsonObject(with: data)
            return json as? [String: Any]
        } catch {
            Log.Core.error("Failed to encode configuration", error: error)
            return nil
        }
    }

    /// Decodes a Codable value from a dictionary representation
    ///
    /// - Parameters:
    ///   - type: The type to decode to
    ///   - dictionary: The dictionary representation
    /// - Returns: The decoded value, or nil if decoding fails
    static func decode<T: Decodable>(_ type: T.Type, from dictionary: [String: Any]) -> T? {
        do {
            let data = try JSONSerialization.data(withJSONObject: dictionary)
            let decoded = try JSONDecoder().decode(type, from: data)
            return decoded
        } catch {
            Log.Core.error("Failed to decode configuration", error: error)
            return nil
        }
    }

    /// Gets a typed value from a configuration dictionary with a default
    ///
    /// - Parameters:
    ///   - key: The key to look up
    ///   - dictionary: The configuration dictionary
    ///   - defaultValue: Default value if key is missing or wrong type
    /// - Returns: The typed value or the default
    static func getValue<T>(_ key: String, from dictionary: [String: Any], default defaultValue: T) -> T {
        guard let value = dictionary[key] as? T else {
            return defaultValue
        }
        return value
    }

    /// Gets an optional typed value from a configuration dictionary
    ///
    /// - Parameters:
    ///   - key: The key to look up
    ///   - dictionary: The configuration dictionary
    /// - Returns: The typed value or nil
    static func getValue<T>(_ key: String, from dictionary: [String: Any]) -> T? {
        return dictionary[key] as? T
    }

    /// Gets an array value from a configuration dictionary
    ///
    /// - Parameters:
    ///   - key: The key to look up
    ///   - dictionary: The configuration dictionary
    /// - Returns: The array or an empty array if not found
    static func getArray<T>(_ key: String, from dictionary: [String: Any]) -> [T] {
        return dictionary[key] as? [T] ?? []
    }

    /// Gets a Codable value from a configuration dictionary
    ///
    /// - Parameters:
    ///   - key: The key to look up
    ///   - type: The type to decode to
    ///   - dictionary: The configuration dictionary
    /// - Returns: The decoded value or nil
    static func getCodable<T: Decodable>(_ key: String, type: T.Type, from dictionary: [String: Any]) -> T? {
        guard let nested = dictionary[key] as? [String: Any] else {
            return nil
        }
        return decode(type, from: nested)
    }

    /// Merges two configuration dictionaries, with the second taking precedence
    ///
    /// - Parameters:
    ///   - base: The base configuration
    ///   - overrides: Values to override
    /// - Returns: The merged configuration
    static func merge(_ base: [String: Any], with overrides: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in overrides {
            if let baseDict = base[key] as? [String: Any],
               let overrideDict = value as? [String: Any] {
                // Recursively merge nested dictionaries
                result[key] = merge(baseDict, with: overrideDict)
            } else {
                result[key] = value
            }
        }
        return result
    }
}

// MARK: - ConfigurationBuilder

/// A fluent builder for creating configuration dictionaries
@resultBuilder
struct ConfigurationBuilder {
    static func buildBlock(_ components: (String, Any)...) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in components {
            result[key] = value
        }
        return result
    }
}

/// Creates a configuration dictionary using a result builder
///
/// Usage:
/// ```swift
/// let config = buildConfiguration {
///     ("key1", "value1")
///     ("key2", 42)
///     ("nested", ["a": 1, "b": 2])
/// }
/// ```
func buildConfiguration(@ConfigurationBuilder _ builder: () -> [String: Any]) -> [String: Any] {
    builder()
}
