import Foundation

/// Represents an extracted artifact from a chat message (code block, document, etc.)
public struct ChatArtifact: Identifiable, Equatable, Hashable, Codable {
    public let id: UUID
    public var title: String
    public var language: String?
    public var content: String
    public var type: ArtifactType

    public enum ArtifactType: String, Codable, Hashable {
        case code
        case markdown
        case html
        case json
        case plainText
    }

    public init(
        id: UUID = UUID(),
        title: String,
        language: String? = nil,
        content: String,
        type: ArtifactType = .code
    ) {
        self.id = id
        self.title = title
        self.language = language
        self.content = content
        self.type = type
    }
}
