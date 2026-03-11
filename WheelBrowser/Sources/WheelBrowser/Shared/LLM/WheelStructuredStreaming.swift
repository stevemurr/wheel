import Foundation
import LanguageModelStructuredOutput

enum WheelStructuredStreamingPrompt {
    static func build<Value>(
        basePrompt: String,
        spec: StructuredOutputSpec<Value>
    ) -> String {
        let schemaText = WheelOutputSchemaPromptRenderer.render(schema: spec.schema)
        return """
        \(basePrompt)

        Return exactly one JSON object and nothing else.
        Do not wrap the JSON in markdown fences.
        Do not add commentary before or after the JSON.
        Use this schema:
        \(schemaText)
        """
    }
}

enum WheelStructuredJSONExtractor {
    static func normalizedJSONObject(in text: String) -> String? {
        guard let firstBrace = text.firstIndex(of: "{"),
              let lastBrace = text.lastIndex(of: "}") else {
            return nil
        }

        guard firstBrace <= lastBrace else {
            return nil
        }

        return String(text[firstBrace...lastBrace])
    }

    static func candidateJSONObjectStrings(in text: String) -> [String] {
        guard let jsonText = normalizedJSONObject(in: text) else {
            return []
        }

        var candidates = [jsonText]
        guard let data = jsonText.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return candidates
        }

        if let nestedResponse = root["response"] as? [String: Any],
           let nestedText = renderJSONObject(nestedResponse) {
            candidates.append(nestedText)
        } else if root.count == 1,
                  let nestedObject = root.values.first as? [String: Any],
                  let nestedText = renderJSONObject(nestedObject) {
            candidates.append(nestedText)
        }

        return candidates
    }

    static func topLevelStringValue(named field: String, in text: String) -> String? {
        guard let keyRange = text.range(of: "\"\(field)\"") else {
            return nil
        }

        var index = keyRange.upperBound
        skipWhitespace(in: text, index: &index)
        guard index < text.endIndex, text[index] == ":" else {
            return nil
        }

        index = text.index(after: index)
        skipWhitespace(in: text, index: &index)
        guard index < text.endIndex, text[index] == "\"" else {
            return nil
        }

        index = text.index(after: index)
        var characters = ""
        var isEscaping = false

        while index < text.endIndex {
            let character = text[index]
            index = text.index(after: index)

            if isEscaping {
                characters.append(decodedEscape(for: character))
                isEscaping = false
                continue
            }

            if character == "\\" {
                isEscaping = true
                continue
            }

            if character == "\"" {
                return characters
            }

            characters.append(character)
        }

        return characters.isEmpty ? nil : characters
    }

    private static func skipWhitespace(in text: String, index: inout String.Index) {
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
    }

    private static func decodedEscape(for character: Character) -> Character {
        switch character {
        case "\"":
            return "\""
        case "\\":
            return "\\"
        case "/":
            return "/"
        case "b":
            return "\u{08}"
        case "f":
            return "\u{0C}"
        case "n":
            return "\n"
        case "r":
            return "\r"
        case "t":
            return "\t"
        default:
            return character
        }
    }

    private static func renderJSONObject(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }
}

enum WheelStructuredStreamAccumulator {
    static func merge(existing: String, incoming: String) -> String {
        if incoming.hasPrefix(existing) {
            return incoming
        }
        if existing.hasPrefix(incoming) {
            return existing
        }
        return existing + incoming
    }
}
