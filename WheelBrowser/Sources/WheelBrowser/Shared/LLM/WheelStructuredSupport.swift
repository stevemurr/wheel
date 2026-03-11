import Foundation
import LanguageModelStructuredOutput

protocol WheelStructuredSpecProviding: Codable, Sendable {
    static var outputSchema: OutputSchema { get }
}

extension WheelStructuredSpecProviding {
    static func structuredSpec(
        transcriptRenderer: @escaping @Sendable (Self) -> String = { value in
            WheelStructuredJSONCodec.compactString(from: value) ?? "{}"
        }
    ) -> StructuredOutputSpec<Self> {
        StructuredOutput.codable(
            Self.self,
            schema: outputSchema,
            renderTranscript: transcriptRenderer
        )
    }
}

enum WheelStructuredJSONCodec {
    static func compactString<Value: Encodable>(from value: Value) -> String? {
        render(value, prettyPrinted: false)
    }

    static func prettyPrintedString<Value: Encodable>(from value: Value) -> String? {
        render(value, prettyPrinted: true)
    }

    private static func render<Value: Encodable>(_ value: Value, prettyPrinted: Bool) -> String? {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }
        guard let data = try? encoder.encode(value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

enum WheelOutputSchema {
    static func string(
        regex: String? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil
    ) -> OutputSchema {
        .string(.init(regex: regex, minLength: minLength, maxLength: maxLength))
    }

    static func integer(
        minimum: Int? = nil,
        maximum: Int? = nil
    ) -> OutputSchema {
        .integer(.init(minimum: minimum, maximum: maximum))
    }

    static func number(
        minimum: Double? = nil,
        maximum: Double? = nil
    ) -> OutputSchema {
        .number(.init(minimum: minimum, maximum: maximum))
    }

    static func boolean() -> OutputSchema {
        .boolean
    }

    static func array(
        item: OutputSchema,
        minimumCount: Int? = nil,
        maximumCount: Int? = nil
    ) -> OutputSchema {
        .array(.init(item: item, minimumCount: minimumCount, maximumCount: maximumCount))
    }

    static func enumeration(
        name: String? = nil,
        cases: [String]
    ) -> OutputSchema {
        .enumeration(.init(name: name, cases: cases))
    }

    static func object(
        name: String,
        description: String? = nil,
        properties: [ObjectSchema.Property]
    ) -> OutputSchema {
        .object(.init(name: name, description: description, properties: properties))
    }

    static func property(
        _ name: String,
        schema: OutputSchema,
        description: String? = nil,
        optional: Bool = false
    ) -> ObjectSchema.Property {
        .init(
            name: name,
            description: description,
            schema: schema,
            isOptional: optional
        )
    }

    static func removingStringLengthConstraints(from schema: OutputSchema) -> OutputSchema {
        switch schema {
        case .string(let constraints):
            return .string(
                .init(
                    regex: constraints.regex,
                    minLength: nil,
                    maxLength: nil
                )
            )
        case .integer, .number, .boolean, .enumeration:
            return schema
        case .array(let constraints):
            return .array(
                .init(
                    item: removingStringLengthConstraints(from: constraints.item),
                    minimumCount: constraints.minimumCount,
                    maximumCount: constraints.maximumCount
                )
            )
        case .object(let object):
            return .object(
                .init(
                    name: object.name,
                    description: object.description,
                    properties: object.properties.map { property in
                        .init(
                            name: property.name,
                            description: property.description,
                            schema: removingStringLengthConstraints(from: property.schema),
                            isOptional: property.isOptional
                        )
                    }
                )
            )
        case .optional(let nested):
            return .optional(removingStringLengthConstraints(from: nested))
        }
    }
}

enum WheelOutputSchemaPromptRenderer {
    static func render(schema: OutputSchema, rootName: String? = nil) -> String {
        render(schema: schema, name: rootName, indent: 0)
    }

    private static func render(schema: OutputSchema, name: String?, indent: Int) -> String {
        let prefix = String(repeating: " ", count: indent)
        let label = name.map { "\"\($0)\": " } ?? ""

        switch schema {
        case .string(let constraints):
            var parts = ["type: string"]
            if let regex = constraints.regex {
                parts.append("regex: \(regex)")
            }
            if let minLength = constraints.minLength {
                parts.append("minLength: \(minLength)")
            }
            if let maxLength = constraints.maxLength {
                parts.append("maxLength: \(maxLength)")
            }
            return "\(prefix)\(label){ \(parts.joined(separator: ", ")) }"
        case .integer(let constraints):
            var parts = ["type: integer"]
            if let minimum = constraints.minimum {
                parts.append("minimum: \(minimum)")
            }
            if let maximum = constraints.maximum {
                parts.append("maximum: \(maximum)")
            }
            return "\(prefix)\(label){ \(parts.joined(separator: ", ")) }"
        case .number(let constraints):
            var parts = ["type: number"]
            if let minimum = constraints.minimum {
                parts.append("minimum: \(minimum)")
            }
            if let maximum = constraints.maximum {
                parts.append("maximum: \(maximum)")
            }
            return "\(prefix)\(label){ \(parts.joined(separator: ", ")) }"
        case .boolean:
            return "\(prefix)\(label){ type: boolean }"
        case .array(let constraints):
            let item = render(schema: constraints.item, name: nil, indent: indent + 2)
                .trimmingCharacters(in: .whitespaces)
            return "\(prefix)\(label){ type: array, item: \(item) }"
        case .object(let object):
            let header = "\(prefix)\(label){"
            let properties = object.properties.map { property in
                let suffix = property.isOptional ? " (optional)" : ""
                return render(schema: property.schema, name: property.name + suffix, indent: indent + 2)
            }
            let footer = "\(prefix)}"
            return ([header] + properties + [footer]).joined(separator: "\n")
        case .enumeration(let enumeration):
            let cases = enumeration.cases.joined(separator: ", ")
            return "\(prefix)\(label){ type: enum, cases: [\(cases)] }"
        case .optional(let nested):
            return render(schema: nested, name: name.map { "\($0) (optional)" }, indent: indent)
        }
    }
}
