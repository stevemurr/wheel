import SwiftUI

struct ChatView: View {
    @ObservedObject var agentManager: AgentManager
    @ObservedObject var tab: Tab
    let contentExtractor: ContentExtractor
    @Binding var isHovered: Bool

    @State private var inputText = ""
    @State private var isSending = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            // Messages
            messagesArea

            // Input
            inputArea
        }
        .padding(12)
        .frame(width: 360)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.3), radius: 20, x: -5, y: 5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .task {
            if !agentManager.isReady && !agentManager.isLoading {
                await agentManager.initialize()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("AI Assistant")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                if let host = tab.url?.host {
                    Text(host)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if agentManager.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
            }

            Menu {
                Button("Clear Chat") {
                    agentManager.clearMessages()
                }
                Button("Store Current Page") {
                    storeCurrentPage()
                }
                Divider()
                Button("Reset Agent", role: .destructive) {
                    Task { await agentManager.resetAgent() }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Messages Area

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    if agentManager.messages.isEmpty {
                        emptyState
                            .padding(.top, 40)
                    } else {
                        ForEach(agentManager.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: agentManager.messages.count) { _, _ in
                if let lastMessage = agentManager.messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 28))
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                Text("Chat with AI")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)

                Text("Ask questions about this page")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            if let error = agentManager.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)

                Button("Retry") {
                    Task { await agentManager.initialize() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: 10) {
            TextField("Ask anything...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...4)
                .focused($isInputFocused)
                .onSubmit {
                    if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        sendMessage()
                    }
                }

            Button(action: sendMessage) {
                ZStack {
                    if isSending {
                        ProgressView()
                            .scaleEffect(0.5)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(inputText.isEmpty ? .secondary : .white)
                    }
                }
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(inputText.isEmpty ? Color.secondary.opacity(0.2) : Color.accentColor)
                )
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func sendMessage() {
        let content = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        inputText = ""
        isSending = true

        Task {
            let pageContext = await contentExtractor.extractContent(from: tab)
            await agentManager.sendMessage(content, pageContext: pageContext)
            isSending = false
        }
    }

    private func storeCurrentPage() {
        Task {
            if let context = await contentExtractor.extractContent(from: tab) {
                await agentManager.storePageVisit(context)
            }
        }
    }
}

// MARK: - Hover Reveal Container

struct AISidebarContainer: View {
    @ObservedObject var agentManager: AgentManager
    @ObservedObject var tab: Tab
    let contentExtractor: ContentExtractor

    @State private var isHovered = false
    @State private var isVisible = false

    var body: some View {
        ZStack(alignment: .trailing) {
            // Invisible hover detection zone on the right edge
            HStack(spacing: 0) {
                Spacer()

                // Hover trigger zone
                Color.clear
                    .frame(width: 60)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering && !isVisible {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                isVisible = true
                                isHovered = true
                            }
                        }
                    }
            }

            // The sidebar itself
            if isVisible {
                ChatView(
                    agentManager: agentManager,
                    tab: tab,
                    contentExtractor: contentExtractor,
                    isHovered: $isHovered
                )
                .onHover { hovering in
                    isHovered = hovering
                    if !hovering {
                        // Delay hiding to allow moving between elements
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if !isHovered {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    isVisible = false
                                }
                            }
                        }
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }

            // Subtle edge indicator when hidden
            if !isVisible {
                VStack {
                    Spacer()

                    // Glowing edge hint
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.0), Color.accentColor.opacity(0.4), Color.accentColor.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3, height: 80)
                        .padding(.trailing, 4)

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .allowsHitTesting(false)
            }
        }
    }
}
