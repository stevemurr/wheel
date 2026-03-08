import SwiftUI

// MARK: - Panel Wrapper

/// Applies shared styling to all OmniBar panels: horizontal padding, bottom spacing, transition, and z-index.
struct PanelWrapperModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
            .zIndex(999)
    }
}

extension View {
    func panelWrapper() -> some View {
        modifier(PanelWrapperModifier())
    }
}

// MARK: - Panel Views

extension OmniBar {
    @ViewBuilder
    var panelViews: some View {
        // Suggestions panel - appears above OmniBar when in address mode (shows tabs + history)
        if isHistoryPanelVisible {
            OmniPanel(
                title: "Go to",
                icon: "magnifyingglass",
                iconColor: .accentColor,
                borderColor: .blue,
                subtitle: historyPanelSubtitle,
                onDismiss: { omniState.dismissVisiblePanel() }
            ) {
                HistoryPanelContent(
                    viewModel: suggestionsVM,
                    searchText: omniState.inputText,
                    onSelect: { suggestion in handleSuggestionSelection(suggestion) }
                )
            }
            .panelWrapper()
        }

        // Chat panel - extracted to isolate agentManager observation (Rule 13)
        ChatOmniPanel(
            agentManager: agentManager,
            omniState: omniState,
            isSending: isSending,
            onDismiss: { omniState.dismissVisiblePanel() },
            onPopulateInput: { text in
                omniState.inputText = text
            }
        )

        // Semantic search panel - extracted to isolate SemanticSearchManagerV2 observation
        SemanticSearchOmniPanel(
            isVisible: isSemanticPanelVisible,
            semanticSearchVM: semanticSearchVM,
            omniState: omniState,
            onDismiss: { omniState.dismissVisiblePanel() },
            onSelect: { result in handleSemanticSelection(result) }
        )

        // Agent panel - appears above OmniBar when in agent mode
        if isAgentPanelVisible {
            AgentOmniPanel(
                agentEngine: agentEngine,
                browserState: browserState,
                onDismiss: { omniState.dismissVisiblePanel() }
            )
            .panelWrapper()
        }

        // Reading list panel - appears above OmniBar when in reading list mode
        if isReadingListPanelVisible {
            OmniPanel(
                title: "Reading List",
                icon: "bookmark.fill",
                iconColor: .pink,
                borderColor: .pink,
                subtitle: readingListPanelSubtitle,
                onDismiss: { omniState.dismissVisiblePanel() }
            ) {
                ReadingListPanelContent(
                    viewModel: readingListVM,
                    searchText: omniState.inputText,
                    onSelect: { item in handleReadingListSelection(item) }
                )
            }
            .panelWrapper()
        }

        // Downloads panel - extracted to isolate DownloadManager observation
        DownloadsOmniPanel()
    }
}

// MARK: - History Panel using OmniPanel

struct HistoryPanelContent: View {
    var viewModel: SuggestionsViewModel
    let searchText: String
    let onSelect: (Suggestion) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: true) {
                LazyVStack(spacing: 2) {
                    if viewModel.suggestions.isEmpty {
                        if searchText.isEmpty {
                            // No history at all
                            OmniPanelEmptyState(
                                icon: "clock",
                                title: "No browsing history",
                                subtitle: "Pages you visit will appear here"
                            )
                            .padding(.top, 30)
                        } else {
                            // No search results
                            OmniPanelEmptyState(
                                icon: "magnifyingglass",
                                title: "No matches found",
                                subtitle: "Try a different search term"
                            )
                            .padding(.top, 30)
                        }
                    } else {
                        // Show suggestions (either search results or recent history)
                        ForEach(Array(viewModel.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                            SuggestionRow(
                                suggestion: suggestion,
                                isSelected: index == viewModel.selectedIndex,
                                onSelect: { onSelect(suggestion) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                if newIndex >= 0 && newIndex < viewModel.suggestions.count {
                    let selectedId = viewModel.suggestions[newIndex].id
                    withAnimation(AppAnimation.quickOut) {
                        proxy.scrollTo(selectedId, anchor: .center)
                    }
                }
            }
        }
    }

    var subtitle: String {
        if !searchText.isEmpty {
            return "\(viewModel.suggestions.count) results"
        }
        return "Recent"
    }
}

// MARK: - Chat Panel using OmniPanel

struct ChatPanelContent: View {
    var agentManager: AgentManager
    var isSending: Bool
    var onSubmitPrompt: ((String) -> Void)?

    var body: some View {
        Group {
            if isSending && agentManager.messages.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)

                    Text("Preparing response…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ChatMessageListView(
                    agentManager: agentManager,
                    onSubmitPrompt: onSubmitPrompt,
                    onSelectArtifact: { artifact in
                        agentManager.selectedArtifact = artifact
                    },
                    compact: true
                )
            }
        }
    }

    var subtitle: String? {
        if isSending || agentManager.isLoading {
            return "Thinking..."
        }
        return nil
    }
}

// MARK: - Chat OmniPanel (isolated sub-view for per-property observation)

/// Extracted from OmniBar to isolate all `agentManager` property reads (messages, isLoading)
/// from the OmniBar body. Only this sub-view re-evaluates when chat messages change during streaming.
private struct ChatOmniPanel: View {
    var agentManager: AgentManager
    var omniState: OmniBarState
    var isSending: Bool
    var onDismiss: () -> Void
    var onPopulateInput: ((String) -> Void)?

    private var isVisible: Bool {
        omniState.isPanelVisible(for: .chat) && !agentManager.isFullPageChatActive
    }

    var body: some View {
        if isVisible {
            OmniPanel(
                title: "Chat",
                icon: "bubble.left.and.bubble.right.fill",
                iconColor: .purple,
                borderColor: .purple,
                subtitle: isSending || agentManager.isLoading ? "Thinking..." : nil,
                menuContent: {
                    Button("Clear Chat") { agentManager.clearMessages() }
                    Divider()
                    Button("Reset Agent", role: .destructive) {
                        Task { await agentManager.resetAgent() }
                    }
                },
                onDismiss: onDismiss
            ) {
                ChatPanelContent(
                    agentManager: agentManager,
                    isSending: isSending,
                    onSubmitPrompt: onPopulateInput
                )
            }
            .modifier(PanelWrapperModifier())
        }
    }
}

// MARK: - Semantic Search OmniPanel (isolated sub-view for per-property observation)

/// Extracted from OmniBar to isolate `SemanticSearchManagerV2` observation.
/// Only this sub-view re-evaluates when the search manager's state changes.
fileprivate struct SemanticSearchOmniPanel: View {
    var isVisible: Bool
    var semanticSearchVM: SemanticSearchViewModel
    var omniState: OmniBarState
    var onDismiss: () -> Void
    var onSelect: (SemanticSearchResult) -> Void

    private var searchManager: SemanticSearchManagerV2 { .shared }

    private var subtitle: String {
        if semanticSearchVM.isSearching {
            return "Searching..."
        } else if !semanticSearchVM.results.isEmpty {
            return "\(semanticSearchVM.results.count) results"
        }
        return "\(searchManager.stats.pageCount) pages indexed"
    }

    var body: some View {
        if isVisible {
            OmniPanel(
                title: "Semantic Search",
                icon: "brain.head.profile",
                iconColor: .orange,
                borderColor: .orange,
                subtitle: subtitle,
                menuContent: {
                    Button("Clear Index") {
                        Task { await searchManager.clearIndex() }
                    }
                },
                onDismiss: onDismiss
            ) {
                SemanticSearchPanelContent(
                    viewModel: semanticSearchVM,
                    searchManager: searchManager,
                    searchText: omniState.inputText,
                    onSelect: { result in onSelect(result) }
                )
            }
            .panelWrapper()
        }
    }
}

// MARK: - Downloads OmniPanel (isolated sub-view for per-property observation)

/// Extracted from OmniBar to isolate `DownloadManager` observation.
/// Only this sub-view re-evaluates when download progress changes.
private struct DownloadsOmniPanel: View {
    private var downloadManager = DownloadManager.shared

    private var subtitle: String {
        downloadManager.panelSubtitle
    }

    var body: some View {
        if downloadManager.showDownloadsPanel {
            OmniPanel(
                title: "Downloads",
                icon: "arrow.down.circle.fill",
                iconColor: .blue,
                borderColor: .blue,
                subtitle: subtitle,
                menuContent: {
                    Button("Clear Completed") { downloadManager.clearCompleted() }
                    Button("Show in Finder") {
                        downloadManager.openDownloadsFolder()
                    }
                },
                onDismiss: { downloadManager.dismissPanel() }
            ) {
                DownloadsPanelContent(manager: downloadManager)
            }
            .panelWrapper()
        }
    }
}

// MARK: - Agent OmniPanel (isolated sub-view for per-property observation)

/// Extracted from OmniBar to isolate all `agentEngine` property reads (subtitle, menu state)
/// from the OmniBar body. With `@Observable`, only this sub-view re-evaluates when agent state changes.
private struct AgentOmniPanel: View {
    var agentEngine: AgentEngine
    var browserState: BrowserState
    var onDismiss: () -> Void

    private var subtitle: String {
        if agentEngine.isRunning {
            return agentEngine.progress
        } else if !agentEngine.steps.isEmpty {
            if let lastStep = agentEngine.steps.last, lastStep.type == .done {
                return "Completed"
            } else if agentEngine.error != nil {
                return "Failed"
            }
            return "\(agentEngine.steps.count) steps"
        }
        return "Ready"
    }

    var body: some View {
        OmniPanel(
            title: "Agent",
            icon: "wand.and.stars",
            iconColor: .green,
            borderColor: .green,
            subtitle: subtitle,
            menuContent: {
                Button("Cancel Task") { agentEngine.cancel() }
                    .disabled(!agentEngine.isRunning)
                Divider()
                Button("Clear History") { agentEngine.steps = [] }
                    .disabled(agentEngine.steps.isEmpty)
            },
            onDismiss: onDismiss
        ) {
            AgentPanelContent(agentEngine: agentEngine, browserState: browserState)
        }
    }
}
