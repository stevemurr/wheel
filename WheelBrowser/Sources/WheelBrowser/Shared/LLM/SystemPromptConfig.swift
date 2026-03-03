import Foundation

/// Unified system prompt configuration for both chat assistant and agent engine.
/// Reads custom prompts from AppSettings when available, otherwise uses defaults.
enum SystemPromptConfig {

    /// Default system prompt for the conversational chat assistant
    static let defaultChatPrompt = """
    You are a helpful AI assistant integrated into a web browser called Wheel.

    Your role is to help users:
    - Understand and summarize web page content
    - Answer questions about pages they're viewing
    - Help with research and information gathering

    When the user asks about the current page, use the page context provided in the message.
    Be concise but helpful. Focus on the most relevant information for the user's question.

    After your response, suggest 2-3 relevant follow-up questions the user might ask. Format them as:
    [SUGGESTIONS]
    - First follow-up question
    - Second follow-up question
    - Third follow-up question
    [/SUGGESTIONS]
    """

    /// Resolved chat system prompt — uses custom if set, otherwise default
    static var chatPrompt: String {
        let custom = AppSettings.shared.chatSystemPrompt
        return custom.isEmpty ? defaultChatPrompt : custom
    }
}
