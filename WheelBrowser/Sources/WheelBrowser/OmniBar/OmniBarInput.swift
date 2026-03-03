import SwiftUI

/// Named constants for OmniBar input pill layout
private enum OmniBarLayout {
    static let collapsedMinWidth: CGFloat = 280
    static let collapsedMaxWidth: CGFloat = 360
    static let expandedMinWidth: CGFloat = 400
    static let expandedMaxWidth: CGFloat = 540
}

// MARK: - Input Pill, Mode Indicator, Action Button

extension OmniBar {
    // MARK: - Input Pill

    var inputPill: some View {
        HStack(spacing: 8) {
            // Mode indicator icon
            modeIndicator

            // Mention chips (only in chat mode)
            if omniState.mode == .chat {
                mentionChips
            }

            // Input field or inline agent status
            if showInlineAgentStatus {
                agentInlineStatus
            } else if omniState.mode == .chat {
                // Multi-line editor for chat mode
                OmniBarTextEditor(
                    text: $omniState.inputText,
                    isFocused: $isInputFocused,
                    placeholder: !omniState.mentions.isEmpty ? "Ask about these pages..." : omniState.placeholder,
                    keyboardHandler: self,
                    onSubmit: handleSubmit,
                    onAtTrigger: { query in
                        handleAtTrigger(query: query)
                    },
                    onAtDismiss: {
                        if omniState.showMentionDropdown {
                            omniState.dismissMentionDropdown()
                            mentionSuggestionsVM.clear()
                        }
                    }
                )
            } else {
                OmniBarTextField(
                    text: $omniState.inputText,
                    isFocused: $isInputFocused,
                    mode: omniState.mode,
                    placeholder: omniState.placeholder,
                    keyboardHandler: self,
                    onSubmit: handleSubmit,
                    onAtTrigger: { query in
                        handleAtTrigger(query: query)
                    },
                    onAtDismiss: {
                        if omniState.showMentionDropdown {
                            omniState.dismissMentionDropdown()
                            mentionSuggestionsVM.clear()
                        }
                    }
                )
            }

            // Action button (clear in address mode, send in chat mode)
            actionButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(
            minWidth: shouldExpand ? OmniBarLayout.expandedMinWidth : OmniBarLayout.collapsedMinWidth,
            maxWidth: shouldExpand ? OmniBarLayout.expandedMaxWidth : OmniBarLayout.collapsedMaxWidth
        )
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(
                    color: isInputFocused ? omniState.modeColor.opacity(0.3) : Color.black.opacity(0.15),
                    radius: isInputFocused ? 8 : 4,
                    x: 0,
                    y: 2
                )
        }
        .overlay {
            Capsule()
                .strokeBorder(
                    isInputFocused ? omniState.modeColor.opacity(0.6) : Color.primary.opacity(0.1),
                    lineWidth: isInputFocused ? 2 : 1
                )
        }
    }

    // MARK: - Mode Indicator

    var modeIndicator: some View {
        HStack(spacing: 4) {
            ModeIndicatorView(
                agentManager: agentManager,
                omniState: omniState,
                isInputFocused: isInputFocused
            )

            // Model selector badge (only in chat mode when focused)
            if omniState.mode == .chat && isInputFocused {
                ModelSelectorBadge()
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
    }

    // MARK: - Action Button

    @ViewBuilder
    var actionButton: some View {
        switch omniState.mode {
        case .address:
            if isInputFocused && !omniState.inputText.isEmpty {
                Button(action: {
                    omniState.inputText = ""
                    suggestionsVM.clear()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }

        case .chat:
            ChatModeActionButton(
                agentManager: agentManager,
                inputText: omniState.inputText,
                isSending: isSending,
                onSubmit: handleSubmit
            )

        case .semantic:
            if isInputFocused && !omniState.inputText.isEmpty {
                Button(action: {
                    omniState.inputText = ""
                    semanticSearchVM.clear()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }

        case .agent:
            AgentActionButton(
                agentEngine: agentEngine,
                inputText: omniState.inputText,
                onSubmit: handleSubmit
            )

        case .readingList:
            if isInputFocused && !omniState.inputText.isEmpty {
                Button(action: {
                    omniState.inputText = ""
                    readingListVM.loadSavedPages()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }

        case .scraping:
            EmptyView() // Scraping mode has no action button
        }
    }

    // MARK: - Inline Agent Status

    /// Show inline status when agent is running but panel is dismissed
    private var showInlineAgentStatus: Bool {
        omniState.mode == .agent
            && agentEngine.isRunning
            && omniState.visiblePanel != .agent
            && !agentEngine.steps.isEmpty
    }

    /// Compact single-line view of the latest agent step, tappable to open panel.
    private var agentInlineStatus: some View {
        AgentInlineStatusView(agentEngine: agentEngine) {
            omniState.setVisiblePanel(.agent)
        }
    }
}

// MARK: - Agent Inline Status (isolated sub-view for per-property observation)

/// Extracted from OmniBar to isolate `streamingThought` and `steps` reads.
/// With `@Observable`, only this sub-view re-evaluates when streaming updates arrive (~15x/sec),
/// not the entire OmniBar body.
private struct AgentInlineStatusView: View {
    var agentEngine: AgentEngine
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if let streamingText = agentEngine.streamingThought, !streamingText.isEmpty {
                    Image(systemName: "brain")
                        .foregroundColor(.purple)
                        .font(.system(size: 11, weight: .medium))

                    Text(streamingText.components(separatedBy: .newlines).last ?? "")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else if let lastStep = agentEngine.steps.last {
                    Image(systemName: agentStepIcon(for: lastStep.type))
                        .foregroundColor(agentStepColor(for: lastStep.type))
                        .font(.system(size: 11, weight: .medium))

                    Text(lastStep.content.components(separatedBy: .newlines).first ?? "")
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func agentStepIcon(for type: AgentStep.StepType) -> String {
        switch type {
        case .observation: return "eye"
        case .thought: return "brain"
        case .action: return "hand.tap"
        case .result: return "checkmark"
        case .error: return "exclamationmark.triangle"
        case .done: return "flag.checkered"
        }
    }

    private func agentStepColor(for type: AgentStep.StepType) -> Color {
        switch type {
        case .observation: return .blue
        case .thought: return .purple
        case .action: return .orange
        case .result: return .green
        case .error: return .red
        case .done: return .green
        }
    }
}

// MARK: - Agent Action Button (isolated sub-view for per-property observation)

/// Extracted from OmniBar to isolate `agentManager.isFullPageChatActive` reads from OmniBar.body.
/// Only this sub-view re-evaluates when the full-page chat state changes.
private struct ModeIndicatorView: View {
    @ObservedObject var agentManager: AgentManager
    @ObservedObject var omniState: OmniBarState
    var isInputFocused: Bool

    var body: some View {
        Button(action: {
            if !agentManager.isFullPageChatActive {
                omniState.nextMode()
            }
        }) {
            Image(systemName: omniState.modeIcon)
                .foregroundColor(isInputFocused ? omniState.modeColor : .secondary)
                .font(.system(size: 12, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(agentManager.isFullPageChatActive)
        .help(agentManager.isFullPageChatActive ? "Chat mode" : "Press Tab to switch modes (Address / Chat / Semantic)")
    }
}

/// Extracted from OmniBar to isolate `agentEngine.isRunning` reads from OmniBar.body.
private struct AgentActionButton: View {
    var agentEngine: AgentEngine
    var inputText: String
    var onSubmit: () -> Void

    var body: some View {
        Button(action: onSubmit) {
            ZStack {
                if agentEngine.isRunning {
                    ProgressView()
                        .scaleEffect(0.5)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(inputText.isEmpty ? .secondary : .white)
                }
            }
            .frame(width: 22, height: 22)
            .background(
                Circle()
                    .fill(inputText.isEmpty ? Color.secondary.opacity(0.2) : Color.green)
            )
        }
        .buttonStyle(.plain)
        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || agentEngine.isRunning)
    }
}

/// Extracted sub-view for chat mode send/stop button (Rule 13).
/// Isolates `agentManager.isStreamingActive` reads from OmniBar.body.
private struct ChatModeActionButton: View {
    @ObservedObject var agentManager: AgentManager
    var inputText: String
    var isSending: Bool
    var onSubmit: () -> Void

    var body: some View {
        if agentManager.isStreamingActive {
            // Stop button during streaming
            Button(action: { agentManager.stopGeneration() }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(Color.red.opacity(0.85))
                    )
            }
            .buttonStyle(.plain)
            .help("Stop generation")
        } else {
            // Send button
            Button(action: onSubmit) {
                ZStack {
                    if isSending {
                        ProgressView()
                            .scaleEffect(0.5)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(inputText.isEmpty ? .secondary : .white)
                    }
                }
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(inputText.isEmpty ? Color.secondary.opacity(0.2) : Color.purple)
                )
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
    }
}
