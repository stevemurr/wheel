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
            modeIndicator

            if currentMentionProvider != nil {
                mentionChips
            }

            if showInlineAgentStatus {
                agentInlineStatus
            } else if featureModel.currentInputKind == .multiLine {
                OmniBarTextEditor(
                    text: $featureModel.inputText,
                    isFocused: $featureModel.isInputFocused,
                    moduleID: featureModel.mode,
                    placeholder: currentMentionProvider != nil && !featureModel.mentions.isEmpty
                        ? "Ask about these pages..."
                        : featureModel.placeholder,
                    supportsMentions: currentMentionProvider != nil,
                    keyboardHandler: self,
                    onSubmit: { featureModel.handleSubmit() },
                    onAtTrigger: { query in
                        currentMentionProvider?.handleMentionTrigger(query: query, in: featureModel)
                    },
                    onAtDismiss: {
                        currentMentionProvider?.dismissMentionSuggestions(in: featureModel)
                    },
                    onHeightChange: { featureModel.chatEditorHeight = $0 }
                )
                .frame(height: featureModel.chatEditorHeight)
            } else {
                OmniBarTextField(
                    text: $featureModel.inputText,
                    isFocused: $featureModel.isInputFocused,
                    moduleID: featureModel.mode,
                    placeholder: featureModel.placeholder,
                    supportsMentions: currentMentionProvider != nil,
                    keyboardHandler: self,
                    onSubmit: { featureModel.handleSubmit() },
                    onAtTrigger: { query in
                        currentMentionProvider?.handleMentionTrigger(query: query, in: featureModel)
                    },
                    onAtDismiss: {
                        currentMentionProvider?.dismissMentionSuggestions(in: featureModel)
                    }
                )
                .frame(height: OmniBarTextEditor.lineHeight + OmniBarTextEditor.verticalPadding)
                .fixedSize(horizontal: false, vertical: true)
            }

            actionButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(
            minWidth: featureModel.shouldExpand ? OmniBarLayout.expandedMinWidth : OmniBarLayout.collapsedMinWidth,
            maxWidth: featureModel.shouldExpand ? OmniBarLayout.expandedMaxWidth : OmniBarLayout.collapsedMaxWidth
        )
        .contentShape(Capsule())
        .simultaneousGesture(
            TapGesture().onEnded {
                featureModel.handleInputPillClick()
            }
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
                radius: featureModel.isInputFocused ? 12 : 6,
                x: 0,
                y: featureModel.isInputFocused ? 6 : 3
            )
        }
        .overlay {
            ZStack {
                Capsule()
                    .strokeBorder(
                        inputPillBorderColor,
                        lineWidth: featureModel.isInputFocused ? 1.5 : 1
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
            featureModel: featureModel,
            isInputFocused: featureModel.isInputFocused,
            isFullPageChatActive: featureModel.isFullPageChatActive
        )
    }

    // MARK: - Action Button

    @ViewBuilder
    var actionButton: some View {
        if let accessory = currentAccessoryProvider?.accessoryView(in: featureModel) {
            accessory
        }
    }

    // MARK: - Inline Agent Status

    /// Show inline status when agent is running but panel is dismissed
    private var showInlineAgentStatus: Bool {
        featureModel.mode == .agent
            && agentEngine.isRunning
            && featureModel.visiblePanel != .agent
            && !agentEngine.steps.isEmpty
    }

    /// Compact single-line view of the latest agent step, tappable to open panel.
    private var agentInlineStatus: some View {
        AgentInlineStatusView(agentEngine: agentEngine) {
            featureModel.setVisiblePanel(.agent)
        }
    }

    private var inputPillBaseFill: Color {
        if currentColorScheme == .dark {
            return Color(nsColor: .controlBackgroundColor).opacity(featureModel.isInputFocused ? 0.92 : 0.84)
        }

        return Color(red: 0.985, green: 0.98, blue: 0.972)
    }

    private var inputPillTintOverlay: Color {
        if currentColorScheme == .dark {
            return featureModel.modeColor.opacity(featureModel.isInputFocused ? 0.10 : 0.04)
        }

        return featureModel.modeColor.opacity(featureModel.isInputFocused ? 0.07 : 0.03)
    }

    private var inputPillBorderColor: Color {
        if featureModel.isInputFocused {
            return featureModel.modeColor.opacity(currentColorScheme == .dark ? 0.58 : 0.42)
        }

        return currentColorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.08)
    }

    private var inputPillInnerHighlight: Color {
        currentColorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.82)
    }

    private var inputPillShadowColor: Color {
        if featureModel.isInputFocused {
            return featureModel.modeColor.opacity(currentColorScheme == .dark ? 0.18 : 0.14)
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

/// Extracted from OmniBar to isolate full-page chat lock UI from the main input pill body.
private struct ModeIndicatorView: View {
    var featureModel: OmniBarFeatureModel
    var isInputFocused: Bool
    var isFullPageChatActive: Bool

    var body: some View {
        Button(action: {
            if !isFullPageChatActive {
                featureModel.nextMode()
            }
        }) {
            Image(systemName: featureModel.modeIcon)
                .foregroundColor(isInputFocused ? featureModel.modeColor : .secondary)
                .font(.system(size: 12, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(isFullPageChatActive)
        .help(isFullPageChatActive ? "Chat mode" : "Press Tab to switch OmniBar modules")
    }
}

/// Extracted from OmniBar to isolate `agentEngine.isRunning` reads from OmniBar.body.
struct AgentActionButton: View {
    var agentEngine: AgentEngine
    var inputText: String
    var onSubmit: () -> Void
    @State private var isAnimating = false

    private var canSubmit: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Button(action: onSubmit) {
            ZStack {
                Circle()
                    .stroke(Color.green.opacity(agentEngine.isRunning ? 0.45 : 0), lineWidth: 1.6)
                    .scaleEffect(agentEngine.isRunning && isAnimating ? 1.34 : 0.92)
                    .opacity(agentEngine.isRunning ? (isAnimating ? 0.18 : 0.36) : 0)

                if agentEngine.isRunning {
                    Circle()
                        .trim(from: 0.12, to: 0.88)
                        .stroke(
                            Color.white.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.7, lineCap: .round)
                        )
                        .frame(width: 12, height: 12)
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))

                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                        .scaleEffect(0.52)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(canSubmit ? .white : .secondary)
                        .offset(x: 0.5)
                }
            }
            .frame(width: 22, height: 22)
            .background(
                Circle()
                    .fill(buttonColor)
            )
            .shadow(
                color: agentEngine.isRunning ? Color.green.opacity(0.45) : .clear,
                radius: agentEngine.isRunning ? 10 : 0
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || agentEngine.isRunning)
        .scaleEffect(agentEngine.isRunning && isAnimating ? 1.04 : 1.0)
        .animation(agentEngine.isRunning ? .linear(duration: 0.95) : .easeInOut(duration: 0.2), value: isAnimating)
        .onAppear {
            updateAnimationState()
        }
        .onChange(of: agentEngine.isRunning) { _, _ in
            updateAnimationState()
        }
    }

    private var buttonColor: Color {
        if agentEngine.isRunning {
            return Color.green.opacity(0.96)
        }
        return canSubmit ? Color.green : Color.secondary.opacity(0.2)
    }

    private func updateAnimationState() {
        if agentEngine.isRunning {
            guard !isAnimating else { return }
            withAnimation(.linear(duration: 0.95).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        } else {
            isAnimating = false
        }
    }
}

/// Extracted sub-view for chat mode send/stop button (Rule 13).
/// Isolates `agentManager.isStreamingActive` reads from OmniBar.body.
struct ChatModeActionButton: View {
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
