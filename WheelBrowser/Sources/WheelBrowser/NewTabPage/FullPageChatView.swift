import SwiftUI

/// Full-page chat view shown on empty tabs when chat mode is active.
/// Replaces `NewTabPageView` with a centered message thread or empty state.
struct FullPageChatView: View {
    var agentManager: AgentManager
    var onSubmitPrompt: ((String) -> Void)?
    @State private var selectedArtifact: ChatArtifact?

    var body: some View {
        HStack(spacing: 0) {
            // Main chat column
            chatColumn
                .frame(maxWidth: .infinity)

            // Artifact panel (slides in from right)
            Group {
                if let artifact = selectedArtifact {
                    Divider()
                    ArtifactPanelView(artifact: artifact) {
                        withAnimation(AppAnimation.standard) {
                            selectedArtifact = nil
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: WindowConstants.cardCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: WindowConstants.cardCornerRadius, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.2), lineWidth: 1)
                    )
                    .padding(.top, 12)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                    .frame(minWidth: 350, maxWidth: 500, maxHeight: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(AppAnimation.standard, value: selectedArtifact != nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Chat Column

    private var chatColumn: some View {
        ChatMessageListView(
            agentManager: agentManager,
            onSubmitPrompt: onSubmitPrompt ?? { text in
                agentManager.pendingInputText = text
            },
            onSelectArtifact: { artifact in
                withAnimation(AppAnimation.standard) {
                    selectedArtifact = artifact
                }
            },
            compact: false
        )
    }
}
