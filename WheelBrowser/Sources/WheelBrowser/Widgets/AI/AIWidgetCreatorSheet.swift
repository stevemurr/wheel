import SwiftUI

/// Sheet for creating AI-generated widgets with a chat interface
struct AIWidgetCreatorSheet: View {
    @ObservedObject var manager: NewTabPageManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AIWidgetCreatorViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Main content: Chat + Preview
            HSplitView {
                chatPanel
                    .frame(minWidth: 300, idealWidth: 350)

                previewPanel
                    .frame(minWidth: 250, idealWidth: 300)
            }
        }
        .frame(width: 700, height: 500)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
            Text("Create AI Widget")
                .font(.system(size: 18, weight: .semibold))

            Spacer()

            if viewModel.previewConfig != nil {
                Button("Add to Page") {
                    addWidget()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isGenerating || viewModel.previewContent.items.isEmpty)
            }

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Chat Panel

    private var chatPanel: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageRow(message: message)
                        }

                        if viewModel.isGenerating {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Generating...")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let lastId = viewModel.messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Example prompts (shown when no config yet)
            if viewModel.previewConfig == nil && viewModel.messages.count <= 1 {
                examplePrompts
            }

            // Input field
            inputField
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var examplePrompts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try these examples:")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(AIWidgetCreatorViewModel.examplePrompts, id: \.self) { prompt in
                    Button {
                        viewModel.inputText = prompt
                    } label: {
                        Text(prompt)
                            .font(.system(size: 11))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var inputField: some View {
        HStack(spacing: 8) {
            TextField("Describe your widget...", text: $viewModel.inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .onSubmit {
                    Task { await viewModel.sendMessage() }
                }

            Button {
                Task { await viewModel.sendMessage() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(viewModel.inputText.isEmpty ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.inputText.isEmpty || viewModel.isGenerating)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Preview Panel

    private var previewPanel: some View {
        VStack(spacing: 0) {
            // Preview header
            HStack {
                Text("Preview")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if viewModel.isLoadingPreview {
                    ProgressView()
                        .scaleEffect(0.6)
                }

                if viewModel.previewConfig != nil {
                    Button {
                        Task { await viewModel.loadPreview() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Refresh preview")
                }
            }
            .padding()

            Divider()

            // Preview content
            if let config = viewModel.previewConfig {
                widgetPreview(config: config)
            } else {
                emptyPreview
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func widgetPreview(config: AIWidgetConfig) -> some View {
        VStack(spacing: 12) {
            // Widget info
            HStack {
                Image(systemName: config.iconName)
                    .foregroundStyle(.purple)
                Text(config.name)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 12)

            // Widget preview box
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    AIWidgetContentView(
                        config: config,
                        content: viewModel.previewContent,
                        size: .medium
                    )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                }
                .padding(.horizontal)

            // Config details
            configDetails(config: config)

            Spacer()
        }
    }

    private func configDetails(config: AIWidgetConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Configuration")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Group {
                LabeledContent("Source", value: config.source.type.rawValue)
                LabeledContent("Layout", value: config.display.layout.rawValue)
                LabeledContent("Refresh", value: "\(config.refresh.intervalMinutes) min")
                LabeledContent("Items", value: "\(config.display.itemLimit)")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
    }

    private var emptyPreview: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)

            Text("Describe your widget\nto see a preview")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func addWidget() {
        guard let widget = viewModel.createWidget() else { return }
        manager.widgets.append(AnyWidget(widget))
        manager.save()
        dismiss()
    }
}

// MARK: - Message Row

struct MessageRow: View {
    let message: AIWidgetCreatorViewModel.ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.system(size: 13))
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(backgroundColor)
                    }
            }

            if message.role != .user {
                Spacer()
            }
        }
        .id(message.id)
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return .accentColor
        case .assistant:
            return Color(nsColor: .controlBackgroundColor)
        case .system:
            return Color(nsColor: .controlBackgroundColor).opacity(0.7)
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let containerWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > containerWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: containerWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
