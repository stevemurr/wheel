import SwiftUI

// MARK: - Chat Panel using OmniPanel

struct ChatPanelContent: View {
    var agentManager: AgentManager
    var onSubmitPrompt: ((String) -> Void)?

    var body: some View {
        ChatMessageListView(
            agentManager: agentManager,
            onSubmitPrompt: onSubmitPrompt,
            onSelectArtifact: { artifact in
                agentManager.selectedArtifact = artifact
            },
            compact: true
        )
    }

    var subtitle: String? {
        if agentManager.isLoading {
            return "Thinking..."
        }
        return nil
    }
}
