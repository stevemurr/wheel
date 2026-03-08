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
                    },
                    onHeightChange: { chatEditorHeight = $0 }
                )
                .frame(height: chatEditorHeight)
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
                .frame(height: OmniBarTextEditor.lineHeight + OmniBarTextEditor.verticalPadding)
                .fixedSize(horizontal: false, vertical: true)
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
            ZStack {
                Capsule()
                    .fill(inputPillBaseFill)

                Capsule()
                    .fill(.ultraThinMaterial)
                    .opacity(currentColorScheme == .dark ? 0.22 : 0.14)

                Capsule()
                    .fill(inputPillTintOverlay)
            }
            .shadow(
                color: inputPillShadowColor,
                radius: isInputFocused ? 12 : 6,
                x: 0,
                y: isInputFocused ? 6 : 3
            )
        }
        .overlay {
            ZStack {
                Capsule()
                    .strokeBorder(
                        inputPillBorderColor,
                        lineWidth: isInputFocused ? 1.5 : 1
                    )

                Capsule()
                    .strokeBorder(inputPillInnerHighlight, lineWidth: 1)
                    .padding(1.5)
            }
        }
    }

    // MARK: - Mode Indicator

    var modeIndicator: some View {
        ModeIndicatorView(
            agentManager: agentManager,
            omniState: omniState,
            isInputFocused: isInputFocused
        )
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

    private var inputPillBaseFill: Color {
        if currentColorScheme == .dark {
            return Color(nsColor: .controlBackgroundColor).opacity(isInputFocused ? 0.92 : 0.84)
        }

        return Color(red: 0.985, green: 0.98, blue: 0.972)
    }

    private var inputPillTintOverlay: Color {
        if currentColorScheme == .dark {
            return omniState.modeColor.opacity(isInputFocused ? 0.10 : 0.04)
        }

        return omniState.modeColor.opacity(isInputFocused ? 0.07 : 0.03)
    }

    private var inputPillBorderColor: Color {
        if isInputFocused {
            return omniState.modeColor.opacity(currentColorScheme == .dark ? 0.58 : 0.42)
        }

        return currentColorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.08)
    }

    private var inputPillInnerHighlight: Color {
        currentColorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.82)
    }

    private var inputPillShadowColor: Color {
        if isInputFocused {
            return omniState.modeColor.opacity(currentColorScheme == .dark ? 0.18 : 0.14)
        }

        return Color.black.opacity(currentColorScheme == .dark ? 0.18 : 0.10)
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
    var agentManager: AgentManager
    var omniState: OmniBarState
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
    @State private var isAnimating = false

    var body: some View {
        Button(action: onSubmit) {
            ZStack {
                Circle()
                    .stroke(Color.green.opacity(agentEngine.isRunning ? 0.35 : 0), lineWidth: 1.5)
                    .scaleEffect(agentEngine.isRunning && isAnimating ? 1.28 : 0.9)
                    .opacity(agentEngine.isRunning ? (isAnimating ? 0.15 : 0.35) : 0)

                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(inputText.isEmpty && !agentEngine.isRunning ? .secondary : .white)
                    .scaleEffect(agentEngine.isRunning && isAnimating ? 1.08 : 1.0)
                    .offset(x: agentEngine.isRunning ? 0.5 : 0)
            }
            .frame(width: 22, height: 22)
            .background(
                Circle()
                    .fill(buttonColor)
            )
        }
        .buttonStyle(.plain)
        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || agentEngine.isRunning)
        .scaleEffect(agentEngine.isRunning && isAnimating ? 1.03 : 1.0)
        .animation(.easeInOut(duration: 0.9), value: isAnimating)
        .onAppear {
            updateAnimationState()
        }
        .onChange(of: agentEngine.isRunning) { _, _ in
            updateAnimationState()
        }
    }

    private var buttonColor: Color {
        if agentEngine.isRunning {
            return Color.green
        }
        return inputText.isEmpty ? Color.secondary.opacity(0.2) : Color.green
    }

    private func updateAnimationState() {
        if agentEngine.isRunning {
            guard !isAnimating else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        } else {
            isAnimating = false
        }
    }
}

/// Extracted sub-view for chat mode send/stop button (Rule 13).
/// Isolates `agentManager.isStreamingActive` reads from OmniBar.body.
private struct ChatModeActionButton: View {
    var agentManager: AgentManager
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

// MARK: - Panel Toggle Button

/// Reusable chevron toggle button for expanding/collapsing OmniBar panels.
/// Used by chat, semantic, agent, and reading list panel toggles.
struct PanelToggleButton: View {
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale))
    }
}

// MARK: - Navigation Button

struct NavigationButton: View {
    let icon: String
    let isEnabled: Bool
    let action: () -> Void

    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isEnabled ? .primary : .secondary.opacity(0.5))
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(isPressed ? Color.accentColor.opacity(0.2) : Color.clear)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(AppAnimation.quick) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - OmniBar Find Bar

struct OmniBarFindBar: View {
    var tab: Tab
    @Binding var findText: String
    @FocusState var isFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Spacer()

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11, weight: .medium))

                    TextField("Find in page", text: $findText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($isFocused)
                        .onChange(of: findText) { _, newValue in
                            tab.findInPage(newValue)
                        }
                        .onSubmit {
                            tab.findNext()
                        }

                    if !findText.isEmpty {
                        Button(action: { findText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: 220)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    Capsule()
                        .strokeBorder(
                            isFocused ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.1),
                            lineWidth: 1
                        )
                }

                HStack(spacing: 4) {
                    Button(action: { tab.findPrevious() }) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(findText.isEmpty ? .secondary.opacity(0.5) : .primary)
                            .frame(width: 28, height: 28)
                            .background {
                                Circle()
                                    .fill(Color.clear)
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(findText.isEmpty)

                    Button(action: { tab.findNext() }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(findText.isEmpty ? .secondary.opacity(0.5) : .primary)
                            .frame(width: 28, height: 28)
                            .background {
                                Circle()
                                    .fill(Color.clear)
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(findText.isEmpty)
                }

                Button(action: {
                    tab.hideFindBar()
                    findText = ""
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background {
                            Circle()
                                .fill(Color.clear)
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Spacer()
        }
    }
}
