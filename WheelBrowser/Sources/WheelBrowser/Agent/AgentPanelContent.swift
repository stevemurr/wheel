import SwiftUI

/// Content view for the Agent panel in OmniBar
struct AgentPanelContent: View {
    @ObservedObject var agentEngine: AgentEngine
    var browserState: BrowserState?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: true) {
                LazyVStack(spacing: 2) {
                    if agentEngine.isRunning || !agentEngine.steps.isEmpty {
                        // Bound tab indicator (shows when running on a background tab)
                        if agentEngine.isRunning, agentEngine.isRunningInBackground,
                           let tabTitle = agentEngine.boundTabTitle {
                            BoundTabIndicator(tabTitle: tabTitle)
                        }

                        // Task name row
                        if !agentEngine.currentTask.isEmpty {
                            AgentTaskRow(
                                task: agentEngine.currentTask,
                                isRunning: agentEngine.isRunning,
                                progress: agentEngine.progress,
                                onCancel: { agentEngine.cancel() },
                                onClear: { agentEngine.steps = [] }
                            )
                        }

                        // Guardrail warning
                        if let warning = agentEngine.guardrailWarning {
                            GuardrailWarningRow(message: warning)
                        }

                        // Step rows
                        ForEach(agentEngine.steps) { step in
                            AgentStepRow(step: step)
                                .id(step.id)
                        }

                        // Streaming thought (live LLM output)
                        if let streamingText = agentEngine.state.streamingThought, !streamingText.isEmpty {
                            AgentStreamingThoughtRow(text: streamingText)
                                .id("streaming-thought")
                        }
                    } else {
                        // Empty state
                        OmniPanelEmptyState(
                            icon: "wand.and.stars",
                            title: "Agent Mode",
                            subtitle: "Describe a task and the agent will automate it"
                        )
                        .padding(.top, 30)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .onChange(of: agentEngine.steps.count) { _, _ in
                if let lastStep = agentEngine.steps.last {
                    withAnimation {
                        proxy.scrollTo(lastStep.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: agentEngine.state.streamingThought) { _, newValue in
                if newValue != nil {
                    withAnimation {
                        proxy.scrollTo("streaming-thought", anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Bound Tab Indicator

private struct BoundTabIndicator: View {
    let tabTitle: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.green)

            Text("Running on:")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Text(tabTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)

            Text("(background)")
                .font(.system(size: 10))
                .foregroundColor(.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.15))
                )

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.green.opacity(0.1))
        )
    }
}

// MARK: - Agent Task Row (matches SuggestionRow structure)

private struct AgentTaskRow: View {
    let task: String
    let isRunning: Bool
    let progress: String
    let onCancel: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon area (28x28 like SuggestionRow favicon)
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 28, height: 28)

                if isRunning {
                    ProgressView()
                        .scaleEffect(0.5)
                } else {
                    Image(systemName: "text.quote")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            // Title and subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(task)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                if isRunning && !progress.isEmpty {
                    Text(progress)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Action button
            if isRunning {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onClear) {
                    Text("Clear")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
    }
}

// MARK: - Agent Step Row (matches SuggestionRow structure)

private struct AgentStepRow: View {
    let step: AgentStep

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Icon area (28x28 like SuggestionRow favicon)
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(iconBackgroundColor)
                    .frame(width: 28, height: 28)

                stepIcon
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(iconColor)
            }

            // Content
            Text(step.content)
                .font(.system(size: 13))
                .foregroundColor(step.type == .error ? .red : .primary)
                .lineLimit(3)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color(nsColor: .controlBackgroundColor).opacity(0.5) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(AppAnimation.quick) {
                isHovering = hovering
            }
        }
    }

    @ViewBuilder
    private var stepIcon: some View {
        switch step.type {
        case .observation:
            Image(systemName: "eye")
        case .thought:
            Image(systemName: "brain")
        case .action:
            Image(systemName: "hand.tap")
        case .result:
            Image(systemName: "checkmark")
        case .error:
            Image(systemName: "exclamationmark.triangle")
        case .done:
            Image(systemName: "flag.checkered")
        }
    }

    private var iconColor: Color {
        switch step.type {
        case .observation: return .blue
        case .thought: return .purple
        case .action: return .orange
        case .result: return .green
        case .error: return .red
        case .done: return .green
        }
    }

    private var iconBackgroundColor: Color {
        iconColor.opacity(0.15)
    }
}

// MARK: - Guardrail Warning Row

private struct GuardrailWarningRow: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.orange)

            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.orange)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.1))
        )
    }
}

// MARK: - Streaming Thought Row

private struct AgentStreamingThoughtRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 28, height: 28)

                Image(systemName: "brain")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.purple)
                    .symbolEffect(.pulse)
            }

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(3)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

#Preview {
    let browserState = BrowserState()
    let engine = AgentEngine(browserState: browserState, settings: AppSettings.shared)
    return AgentPanelContent(agentEngine: engine, browserState: browserState)
        .frame(width: 400, height: 300)
        .background(Color(nsColor: .windowBackgroundColor))
}
