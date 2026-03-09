import Foundation

enum NoteKind: String, Codable, CaseIterable, Sendable {
    case daily
    case adhoc
}

struct NotePageSource: Codable, Equatable, Sendable {
    let title: String
    let url: String
    let capturedAt: Date

    init(title: String, url: String, capturedAt: Date = Date()) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? url : title
        self.url = url
        self.capturedAt = capturedAt
    }
}

struct NoteDocument: Codable, Sendable {
    var root: [String: AnyCodable]

    init(root: [String: AnyCodable]) {
        self.root = root
    }

    static var empty: NoteDocument {
        NoteDocument(
            root: [
                "type": AnyCodable("doc"),
                "content": AnyCodable([Self.emptyParagraphNode]),
            ]
        )
    }

    static func titled(_ title: String) -> NoteDocument {
        let normalizedTitle = Self.normalizeLine(title)
        guard !normalizedTitle.isEmpty else { return .empty }

        return NoteDocument(
            root: [
                "type": AnyCodable("doc"),
                "content": AnyCodable([Self.paragraphNode(text: normalizedTitle)]),
            ]
        )
    }

    func plainText(maxLength: Int = 180) -> String {
        let text = Self.documentLines(from: Self.normalizedJSON(root))
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Self.truncated(text, maxLength: maxLength)
    }

    func titleLine(maxLength: Int = 120) -> String {
        let line = Self.documentLines(from: Self.normalizedJSON(root)).first ?? ""
        return Self.truncated(line, maxLength: maxLength)
    }

    func previewText(maxLength: Int = 180) -> String {
        let lines = Self.documentLines(from: Self.normalizedJSON(root))
        let text = Array(lines.dropFirst())
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Self.truncated(text, maxLength: maxLength)
    }

    var canonicalJSONString: String? {
        let normalized = Self.normalizedJSON(root)
        guard JSONSerialization.isValidJSONObject(normalized),
              let data = try? JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys]) else {
            return nil
        }

        return String(decoding: data, as: UTF8.self)
    }

    func migratedForInlineTitle(_ legacyTitle: String) -> NoteDocument {
        let normalizedTitle = Self.normalizeLine(legacyTitle)
        guard !normalizedTitle.isEmpty, titleLine(maxLength: Int.max).isEmpty else {
            return self
        }

        var updatedRoot = root
        var content = updatedRoot["content"]?.arrayValue ?? []
        content.insert(Self.paragraphNode(text: normalizedTitle), at: 0)
        updatedRoot["content"] = AnyCodable(content)
        return NoteDocument(root: updatedRoot)
    }

    func insertingPageSource(_ source: NotePageSource) -> NoteDocument {
        var updatedRoot = root
        var content = updatedRoot["content"]?.arrayValue ?? []
        let attrs: [String: Any] = [
            "title": source.title,
            "url": source.url,
            "capturedAt": Self.iso8601.string(from: source.capturedAt),
        ]

        let pageNode: [String: Any] = [
            "type": "pageSource",
            "attrs": attrs,
        ]

        if Self.isEffectivelyEmptyContent(content) {
            content = [pageNode, Self.emptyParagraphNode]
        } else {
            if let last = content.last, !Self.isEmptyParagraphNode(last) {
                content.append(Self.emptyParagraphNode)
            }
            content.append(pageNode)
            content.append(Self.emptyParagraphNode)
        }

        updatedRoot["content"] = AnyCodable(content)
        return NoteDocument(root: updatedRoot)
    }

    private static let emptyParagraphNode: [String: Any] = [
        "type": "paragraph",
        "content": [],
    ]

    private static func paragraphNode(text: String) -> [String: Any] {
        [
            "type": "paragraph",
            "content": [
                [
                    "type": "text",
                    "text": text,
                ],
            ],
        ]
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func documentLines(from value: Any) -> [String] {
        blockTextLines(from: value)
            .flatMap { $0.components(separatedBy: .newlines) }
            .map(normalizeLine)
            .filter { !$0.isEmpty }
    }

    private static func blockTextLines(from value: Any) -> [String] {
        switch value {
        case let wrapped as AnyCodable:
            return blockTextLines(from: wrapped.value)

        case let dictionary as [String: Any]:
            if let type = dictionary["type"] as? String {
                switch type {
                case "doc", "bulletList", "orderedList", "taskList", "listItem", "taskItem", "table":
                    return blockTextLines(from: dictionary["content"] ?? [])
                case "tableRow":
                    return blockTextLines(from: dictionary["content"] ?? [])
                case "paragraph", "heading":
                    let text = inlineText(from: dictionary["content"] ?? [])
                    return text.isEmpty ? [] : [text]
                case "blockquote", "tableCell", "tableHeader":
                    return blockTextLines(from: dictionary["content"] ?? [])
                case "codeBlock":
                    return inlineText(from: dictionary["content"] ?? [])
                        .components(separatedBy: .newlines)
                        .filter { !$0.isEmpty }
                case "pageSource":
                    if let attrs = dictionary["attrs"] as? [String: Any] {
                        let title = attrs["title"] as? String ?? "Source"
                        let url = attrs["url"] as? String ?? ""
                        let text = [title, url].filter { !$0.isEmpty }.joined(separator: " ")
                        return text.isEmpty ? [] : [text]
                    }
                default:
                    break
                }
            }

            if let content = dictionary["content"] {
                return blockTextLines(from: content)
            }

            return []

        case let array as [Any]:
            return array
                .flatMap(blockTextLines(from:))

        default:
            return []
        }
    }

    private static func inlineText(from value: Any) -> String {
        switch value {
        case let wrapped as AnyCodable:
            return inlineText(from: wrapped.value)

        case let dictionary as [String: Any]:
            if let type = dictionary["type"] as? String {
                switch type {
                case "text":
                    return dictionary["text"] as? String ?? ""
                case "hardBreak":
                    return "\n"
                case "pageSource":
                    if let attrs = dictionary["attrs"] as? [String: Any] {
                        let title = attrs["title"] as? String ?? "Source"
                        let url = attrs["url"] as? String ?? ""
                        return [title, url].filter { !$0.isEmpty }.joined(separator: " ")
                    }
                default:
                    break
                }
            }

            if let content = dictionary["content"] {
                return inlineText(from: content)
            }

            return ""

        case let array as [Any]:
            return array
                .map(inlineText(from:))
                .joined()

        default:
            return ""
        }
    }

    private static func isEffectivelyEmptyContent(_ content: [Any]) -> Bool {
        content.isEmpty || content.allSatisfy(isEmptyParagraphNode)
    }

    private static func isEmptyParagraphNode(_ value: Any) -> Bool {
        let nodeValue = (value as? AnyCodable)?.value ?? value
        guard let dictionary = nodeValue as? [String: Any],
              dictionary["type"] as? String == "paragraph" else {
            return false
        }

        if let wrapped = dictionary["content"] as? AnyCodable {
            return wrapped.arrayValue?.isEmpty ?? false
        }

        if let array = dictionary["content"] as? [Any] {
            return array.isEmpty
        }

        return dictionary["content"] == nil
    }

    private static func normalizedJSON(_ value: Any) -> Any {
        switch value {
        case let wrapped as AnyCodable:
            return normalizedJSON(wrapped.value)

        case let dictionary as NSDictionary:
            var normalized: [String: Any] = [:]
            for (key, nestedValue) in dictionary {
                guard let key = key as? String else { continue }
                normalized[key] = normalizedJSON(nestedValue)
            }
            return normalized

        case let array as NSArray:
            return array.map(normalizedJSON)

        default:
            return value
        }
    }

    private static func normalizeLine(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncated(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let index = text.index(text.startIndex, offsetBy: maxLength)
        return String(text[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

struct NoteRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let workspaceID: UUID
    let kind: NoteKind
    var title: String
    let dayIdentifier: String?
    let createdAt: Date
    var updatedAt: Date
    var excerpt: String
    var document: NoteDocument

    init(
        id: UUID = UUID(),
        workspaceID: UUID,
        kind: NoteKind,
        title: String,
        dayIdentifier: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        excerpt: String = "",
        document: NoteDocument = .empty
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.kind = kind
        self.title = title
        self.dayIdentifier = dayIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.excerpt = excerpt
        self.document = document
    }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Note" : title
    }

    var shortUpdatedText: String {
        updatedAt.abbreviatedRelativeTimeString()
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}
