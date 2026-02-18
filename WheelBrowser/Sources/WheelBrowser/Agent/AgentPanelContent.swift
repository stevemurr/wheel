import SwiftUI

/// Content view for the Agent panel in OmniBar
struct AgentPanelContent: View {
    @ObservedObject var agentEngine: AgentEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if agentEngine.isRunning {
                runningView
            } else if !agentEngine.steps.isEmpty {
                resultsView
            } else {
                emptyView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Running View

    private var runningView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Task header
            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)

                Text(agentEngine.currentTask)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)

                Spacer()

                Button(action: { agentEngine.cancel() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Cancel task")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            // Progress indicator
            HStack {
                Text(agentEngine.progress)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)

            Divider()
                .padding(.vertical, 4)

            // Steps list
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(agentEngine.steps) { step in
                            StepRow(step: step)
                                .id(step.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .frame(maxHeight: 300)
                .onChange(of: agentEngine.steps.count) { _, _ in
                    if let lastStep = agentEngine.steps.last {
                        withAnimation {
                            proxy.scrollTo(lastStep.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Results View

    private var resultsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                if let lastStep = agentEngine.steps.last, lastStep.type == .done {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14))
                    Text("Task Complete")
                        .font(.system(size: 13, weight: .medium))
                } else if agentEngine.error != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 14))
                    Text("Task Failed")
                        .font(.system(size: 13, weight: .medium))
                } else {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                    Text("Previous Task")
                        .font(.system(size: 13, weight: .medium))
                }

                Spacer()

                Button(action: { agentEngine.steps = [] }) {
                    Text("Clear")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            // Task name
            if !agentEngine.currentTask.isEmpty {
                Text(agentEngine.currentTask)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
            }

            Divider()
                .padding(.vertical, 4)

            // Steps summary
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(agentEngine.steps) { step in
                        StepRow(step: step)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .frame(maxHeight: 300)
        }
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Agent Mode")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            Text("Describe a task and the agent will automate it")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Step Row

private struct StepRow: View {
    let step: AgentStep

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            stepIcon
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.content)
                    .font(.system(size: 11))
                    .foregroundColor(textColor)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var stepIcon: some View {
        switch step.type {
        case .observation:
            Image(systemName: "eye")
                .foregroundColor(.blue)
                .font(.system(size: 10))
        case .thought:
            Image(systemName: "brain")
                .foregroundColor(.purple)
                .font(.system(size: 10))
        case .action:
            Image(systemName: "hand.tap")
                .foregroundColor(.orange)
                .font(.system(size: 10))
        case .result:
            Image(systemName: "checkmark")
                .foregroundColor(.green)
                .font(.system(size: 10))
        case .error:
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.red)
                .font(.system(size: 10))
        case .done:
            Image(systemName: "flag.checkered")
                .foregroundColor(.green)
                .font(.system(size: 10))
        }
    }

    private var backgroundColor: Color {
        switch step.type {
        case .observation:
            return Color.blue.opacity(0.1)
        case .thought:
            return Color.purple.opacity(0.1)
        case .action:
            return Color.orange.opacity(0.1)
        case .result:
            return Color.green.opacity(0.1)
        case .error:
            return Color.red.opacity(0.1)
        case .done:
            return Color.green.opacity(0.15)
        }
    }

    private var textColor: Color {
        switch step.type {
        case .error:
            return .red
        default:
            return .primary
        }
    }
}

#Preview {
    let engine = AgentEngine(browserState: BrowserState(), settings: AppSettings.shared)
    return AgentPanelContent(agentEngine: engine)
        .frame(width: 400, height: 300)
        .background(Color(nsColor: .windowBackgroundColor))
}
