import Foundation

/// A unified chat message model for use across the application.
public struct ChatMessage: Identifiable, Equatable, Hashable, Codable {
    public let id: UUID
    public let role: MessageRole
    public var content: String
    public var modelContent: String?
    public let timestamp: Date
    public var isStreaming: Bool

    // MARK: - Metadata (optional, for persistence & diagnostics)

    public var tokens: Int?
    public var modelUsed: String?
    public var conversationId: UUID?
    public var isFailed: Bool

    // MARK: - Thinking duration

    /// Duration the model spent thinking (set after stream completes)
    public var thinkingDurationSeconds: TimeInterval?
    /// When thinking started (for live timer during streaming)
    public var thinkingStartTime: Date?

    // MARK: - Follow-up suggestions

    /// AI-suggested follow-up prompts parsed from model output
    public var suggestedFollowUps: [String]

    // MARK: - Context badges

    /// Structured context sources shown alongside the message in the chat UI.
    public var contextBadges: [ChatContextBadge]?

    /// Context fingerprints that were actually injected into the model-visible prompt.
    public var injectedContextKeys: [String]?

    // MARK: - Stop generation

    /// Whether the user stopped generation mid-stream
    public var wasStoppedByUser: Bool

    // MARK: - Artifacts

    /// Extracted code blocks / documents from this message
    public var artifacts: [ChatArtifact]

    // MARK: - Branching (edit / regenerate)

    /// The original message ID this is a branch of
    public var parentId: UUID?
    /// Which branch variant this is (0-based)
    public var branchIndex: Int
    /// Total number of branches at this point
    public var totalBranches: Int

    /// The role of the message sender
    public enum MessageRole: String, Codable, Hashable {
        case user
        case assistant
        case system
        case thinking
    }

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        modelContent: String? = nil,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        tokens: Int? = nil,
        modelUsed: String? = nil,
        conversationId: UUID? = nil,
        isFailed: Bool = false,
        thinkingDurationSeconds: TimeInterval? = nil,
        thinkingStartTime: Date? = nil,
        suggestedFollowUps: [String] = [],
        contextBadges: [ChatContextBadge]? = nil,
        injectedContextKeys: [String]? = nil,
        wasStoppedByUser: Bool = false,
        artifacts: [ChatArtifact] = [],
        parentId: UUID? = nil,
        branchIndex: Int = 0,
        totalBranches: Int = 1
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.modelContent = modelContent
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.tokens = tokens
        self.modelUsed = modelUsed
        self.conversationId = conversationId
        self.isFailed = isFailed
        self.thinkingDurationSeconds = thinkingDurationSeconds
        self.thinkingStartTime = thinkingStartTime
        self.suggestedFollowUps = suggestedFollowUps
        self.contextBadges = contextBadges
        self.injectedContextKeys = injectedContextKeys
        self.wasStoppedByUser = wasStoppedByUser
        self.artifacts = artifacts
        self.parentId = parentId
        self.branchIndex = branchIndex
        self.totalBranches = totalBranches
    }

    // MARK: - Convenience Initializers

    /// Create a user message
    public static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }

    /// Create an assistant message
    public static func assistant(_ content: String, streaming: Bool = false) -> ChatMessage {
        ChatMessage(role: .assistant, content: content, isStreaming: streaming)
    }

    /// Create a system message
    public static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: .system, content: content)
    }

    /// Create a thinking/reasoning message (for chain-of-thought display)
    public static func thinking(_ content: String) -> ChatMessage {
        ChatMessage(role: .thinking, content: content)
    }

    // MARK: - Equatable

    public static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id &&
        lhs.content == rhs.content &&
        lhs.modelContent == rhs.modelContent &&
        lhs.isStreaming == rhs.isStreaming &&
        lhs.isFailed == rhs.isFailed &&
        lhs.contextBadges == rhs.contextBadges &&
        lhs.injectedContextKeys == rhs.injectedContextKeys
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(content)
        hasher.combine(modelContent)
        hasher.combine(isStreaming)
        hasher.combine(isFailed)
        hasher.combine(contextBadges)
        hasher.combine(injectedContextKeys)
    }
}

// MARK: - Array Extension for Conversation

extension Array where Element == ChatMessage {
    /// Convert to LLM API message format
    public func toAPIMessages() -> [[String: String]] {
        map { message in
            [
                "role": message.role == .thinking ? "assistant" : message.role.rawValue,
                "content": message.content
            ]
        }
    }

    /// Get the last message from a specific role
    public func lastMessage(from role: ChatMessage.MessageRole) -> ChatMessage? {
        last { $0.role == role }
    }

    /// Check if conversation has any streaming messages
    public var hasStreamingMessages: Bool {
        contains { $0.isStreaming }
    }
}
