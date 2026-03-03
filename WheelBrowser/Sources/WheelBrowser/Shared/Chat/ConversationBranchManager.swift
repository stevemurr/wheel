import Foundation

/// Manages edit/regenerate branching for conversation messages.
/// Uses a flat array with `parentId` references; only the active branch is displayed.
enum ConversationBranchManager {

    /// Edit a user message and fork the conversation.
    /// Returns the new messages array with the edited message and truncated history.
    static func editMessage(
        at index: Int,
        newContent: String,
        in messages: [ChatMessage]
    ) -> [ChatMessage] {
        guard index >= 0, index < messages.count else { return messages }
        let original = messages[index]

        // Keep messages before the edited one
        var newMessages = Array(messages.prefix(index))

        // Create the edited message with branch info
        let editedMessage = ChatMessage(
            role: original.role,
            content: newContent,
            timestamp: Date(),
            parentId: original.parentId ?? original.id,
            branchIndex: original.branchIndex + 1,
            totalBranches: original.totalBranches + 1
        )
        newMessages.append(editedMessage)

        return newMessages
    }

    /// Regenerate an assistant response at the given index.
    /// Returns the new messages array with the assistant message removed (ready for re-generation).
    static func regenerateResponse(
        at index: Int,
        in messages: [ChatMessage]
    ) -> [ChatMessage] {
        guard index >= 0, index < messages.count else { return messages }
        let original = messages[index]
        guard original.role == .assistant else { return messages }

        // Keep messages before the assistant response (and any preceding thinking)
        var truncateIndex = index
        if truncateIndex > 0, messages[truncateIndex - 1].role == .thinking {
            truncateIndex -= 1
        }

        var newMessages = Array(messages.prefix(truncateIndex))

        // Update branch info on the parent user message if it exists
        if let lastIdx = newMessages.lastIndex(where: { $0.role == .user }) {
            newMessages[lastIdx].totalBranches += 1
        }

        return newMessages
    }
}
