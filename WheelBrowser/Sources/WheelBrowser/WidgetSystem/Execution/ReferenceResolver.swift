import Foundation

/// Resolves `{{step_id.output}}` references in pipeline step parameters.
enum ReferenceResolver {
    /// Pattern matching `{{step_id.output}}` references.
    private static let refPattern = try! NSRegularExpression(pattern: #"\{\{(\w+)\.output\}\}"#)

    /// Resolve all references in a params dictionary using the execution context.
    /// - Parameters:
    ///   - params: The raw params dictionary (may contain string references)
    ///   - context: Map of step_id → output from previously executed steps
    /// - Returns: A new params dictionary with all references resolved
    static func resolve(params: [String: AnyCodable], context: [String: Any]) throws -> [String: Any] {
        var resolved: [String: Any] = [:]
        for (key, codableValue) in params {
            resolved[key] = try resolveValue(codableValue.value, context: context)
        }
        return resolved
    }

    private static func resolveValue(_ value: Any, context: [String: Any]) throws -> Any {
        if let string = value as? String {
            return try resolveString(string, context: context)
        }
        if let array = value as? [Any] {
            return try array.map { try resolveValue($0, context: context) }
        }
        if let dict = value as? [String: Any] {
            var resolved: [String: Any] = [:]
            for (k, v) in dict {
                resolved[k] = try resolveValue(v, context: context)
            }
            return resolved
        }
        return value
    }

    private static func resolveString(_ string: String, context: [String: Any]) throws -> Any {
        let range = NSRange(string.startIndex..., in: string)
        let matches = refPattern.matches(in: string, range: range)

        guard !matches.isEmpty else { return string }

        // If the entire string is a single reference, return the raw value (preserving type)
        if matches.count == 1,
           let matchRange = Range(matches[0].range, in: string),
           string[matchRange] == string {
            let stepId = String(string[Range(matches[0].range(at: 1), in: string)!])
            guard let output = context[stepId] else {
                throw WidgetError.invalidReference(stepId: "", ref: stepId)
            }
            return output
        }

        // Multiple references or mixed text — build result by walking the original
        // string forward, copying literal segments and inserting resolved values.
        var result = ""
        var cursor = string.startIndex
        for match in matches {
            let stepId = String(string[Range(match.range(at: 1), in: string)!])
            guard let output = context[stepId] else {
                throw WidgetError.invalidReference(stepId: "", ref: stepId)
            }
            guard let matchRange = Range(match.range, in: string) else {
                continue
            }
            // Append the literal text before this match
            result += string[cursor..<matchRange.lowerBound]
            // Append the resolved value
            result += "\(output)"
            cursor = matchRange.upperBound
        }
        // Append any trailing literal text
        result += string[cursor...]
        return result
    }
}
