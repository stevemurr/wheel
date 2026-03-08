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
                "content": AnyCodable([
                    [
                        "type": "paragraph",
                        "content": [],
                    ],
                ]),
            ]
        )
    }

    func plainText(maxLength: Int = 180) -> String {
        let text = Self.extractPlainText(from: Self.normalizedJSON(root))
            .replacingOccurrences(of: "\n{2,}", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard text.count > maxLength else { return text }
        let index = text.index(text.startIndex, offsetBy: maxLength)
        return String(text[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
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

        let needsSeparator = !content.isEmpty
        if needsSeparator {
            content.append([
                "type": "paragraph",
                "content": [],
            ])
        }
        content.append(pageNode)
        content.append([
            "type": "paragraph",
            "content": [],
        ])

        updatedRoot["content"] = AnyCodable(content)
        return NoteDocument(root: updatedRoot)
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func extractPlainText(from value: Any) -> String {
        switch value {
        case let wrapped as AnyCodable:
            return extractPlainText(from: wrapped.value)

        case let dictionary as [String: Any]:
            if let type = dictionary["type"] as? String {
                switch type {
                case "text":
                    return dictionary["text"] as? String ?? ""
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
                return extractPlainText(from: content)
            }

            return dictionary.values
                .map(extractPlainText(from:))
                .filter { !$0.isEmpty }
                .joined(separator: " ")

        case let array as [Any]:
            return array
                .map(extractPlainText(from:))
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

        default:
            return ""
        }
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
        switch kind {
        case .daily:
            if let dayIdentifier {
                return Self.displayDateFormatter.string(from: NoteRecord.dayFormatter.date(from: dayIdentifier) ?? createdAt)
            }
            return title
        case .adhoc:
            return title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Note" : title
        }
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
