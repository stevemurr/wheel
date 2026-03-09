import Foundation

/// Assembles conversation context for LLM API calls.
///
/// Responsible for:
/// - Prepending the system prompt to conversation history
/// - Formatting page contexts into the user message
/// - Building the final messages array in the format expected by OpenAI-compatible APIs
struct ConversationHistoryBuilder {

    /// Build the full API messages array by prepending the system prompt
    /// to the existing conversation history.
    ///
    /// - Parameters:
    ///   - systemPrompt: The system prompt to use for the conversation.
    ///   - conversationHistory: The existing conversation history as role/content dictionaries.
    /// - Returns: An array of message dictionaries ready for the API request body.
    static func buildAPIMessages(
        systemPrompt: String,
        conversationHistory: [[String: String]]
    ) -> [[String: String]] {
        var apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        apiMessages.append(contentsOf: conversationHistory)
        return apiMessages
    }

    /// Build a full user message by combining page contexts with the user's question.
    ///
    /// When page contexts are provided, they are formatted as structured blocks
    /// preceding the user's question. When no contexts are provided, the original
    /// content is returned unchanged.
    ///
    /// - Parameters:
    ///   - content: The user's raw question or message.
    ///   - pageContexts: Zero or more page contexts to include.
    /// - Returns: The assembled message string suitable for the conversation history.
    static func buildFullMessage(content: String, pageContexts: [PageContext]) -> String {
        guard !pageContexts.isEmpty else { return content }

        var contextParts: [String] = []
        for (index, context) in pageContexts.enumerated() {
            let header = pageContexts.count == 1 ? "[Page Context]" : "--- Page \(index + 1) ---"
            contextParts.append("""
            \(header)
            URL: \(context.url)
            Title: \(context.title)
            Content Preview:
            \(context.textContent.prefix(4000))
            """)
        }

        return """
        \(contextParts.joined(separator: "\n\n"))

        [User Question]
        \(content)
        """
    }

    static func pageContextsRequiringInjection(
        _ pageContexts: [PageContext],
        previouslyInjectedContextKeys: Set<String>
    ) -> [PageContext] {
        var seenContextKeys = previouslyInjectedContextKeys

        return pageContexts.filter { context in
            guard let contextKey = injectedContextKey(for: context) else {
                return true
            }

            return seenContextKeys.insert(contextKey).inserted
        }
    }

    static func injectedContextKeys(for pageContexts: [PageContext]) -> [String] {
        pageContexts.compactMap(injectedContextKey(for:))
    }

    /// Rebuild conversation history from persisted messages.
    ///
    /// Filters to only user and assistant messages, converting them to the
    /// dictionary format expected by the conversation history array.
    ///
    /// - Parameter messages: The full list of chat messages (may include thinking, system, etc.)
    /// - Returns: An array of role/content dictionaries for user and assistant messages only.
    static func rebuildHistory(from messages: [ChatMessage]) -> [[String: String]] {
        messages
            .filter { $0.role == .user || $0.role == .assistant }
            .map { ["role": $0.role.rawValue, "content": $0.content] }
    }

    private static func injectedContextKey(for context: PageContext) -> String? {
        guard context.contextBadge.kind == .website else {
            return nil
        }

        let normalizedText = context.textContent
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let truncatedText = String(normalizedText.prefix(4000))

        return [
            context.contextBadge.kind.rawValue,
            context.url,
            context.title,
            truncatedText,
        ].joined(separator: "\n")
    }
}
