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
            onDismiss: { omniState.dismissVisiblePanel() },
            onPopulateInput: { text in
                omniState.inputText = text
            }
        )

        // Semantic search panel - appears above OmniBar when in semantic mode
        if isSemanticPanelVisible {
            OmniPanel(
                title: "Semantic Search",
                icon: "brain.head.profile",
                iconColor: .orange,
                borderColor: .orange,
                subtitle: semanticPanelSubtitle,
                menuContent: {
                    AnyView(Group {
                        Button("Clear Index") {
                            Task { await semanticSearchManager.clearIndex() }
                        }
                    })
                },
                onDismiss: { omniState.dismissVisiblePanel() }
            ) {
                SemanticSearchPanelContent(
                    viewModel: semanticSearchVM,
                    searchManager: semanticSearchManager,
                    searchText: omniState.inputText,
                    onSelect: { result in handleSemanticSelection(result) }
                )
            }
            .panelWrapper()
        }

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

        // Downloads panel - appears above OmniBar when downloads are active
        if downloadManager.showDownloadsPanel {
            OmniPanel(
                title: "Downloads",
                icon: "arrow.down.circle.fill",
                iconColor: .blue,
                borderColor: .blue,
                subtitle: downloadsPanelSubtitle,
                menuContent: {
                    AnyView(Group {
                        Button("Clear Completed") { downloadManager.clearCompleted() }
                        Button("Show in Finder") {
                            downloadManager.openDownloadsFolder()
                        }
                    })
                },
                onDismiss: { downloadManager.dismissPanel() }
            ) {
                DownloadsPanelContent(manager: downloadManager)
            }
            .panelWrapper()
        }

        // Scrape panel - appears above OmniBar when in scraping mode
        if isScrapingPanelVisible {
            OmniPanel(
                title: "Web Scraping",
                icon: "network",
                iconColor: .cyan,
                borderColor: .cyan,
                subtitle: scrapePanelSubtitle,
                menuContent: {
                    AnyView(Group {
                        Button("New Scrape...") {
                            NotificationCenter.default.post(name: .scrapePage, object: nil)
                        }
                        Divider()
                        Button("Clear Completed") { scrapeManager.clearCompleted() }
                    })
                },
                onDismiss: {
                    omniState.dismissVisiblePanel()
                    if omniState.mode == .scraping {
                        omniState.mode = .address
                    }
                }
            ) {
                ScrapePanelContent(manager: scrapeManager)
            }
            .panelWrapper()
        }
    }
}

// MARK: - Chat OmniPanel (isolated sub-view for per-property observation)

/// Extracted from OmniBar to isolate all `agentManager` property reads (messages, isLoading)
/// from the OmniBar body. Only this sub-view re-evaluates when chat messages change during streaming.
private struct ChatOmniPanel: View {
    var agentManager: AgentManager
    @ObservedObject var omniState: OmniBarState
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
                subtitle: agentManager.isLoading ? "Thinking..." : nil,
                menuContent: {
                    AnyView(Group {
                        Button("Clear Chat") { agentManager.clearMessages() }
                        Divider()
                        Button("Reset Agent", role: .destructive) {
                            Task { await agentManager.resetAgent() }
                        }
                    })
                },
                onDismiss: onDismiss
            ) {
                ChatPanelContent(agentManager: agentManager, onSubmitPrompt: onPopulateInput)
            }
            .modifier(PanelWrapperModifier())
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
                AnyView(Group {
                    Button("Cancel Task") { agentEngine.cancel() }
                        .disabled(!agentEngine.isRunning)
                    Divider()
                    Button("Clear History") { agentEngine.steps = [] }
                        .disabled(agentEngine.steps.isEmpty)
                })
            },
            onDismiss: onDismiss
        ) {
            AgentPanelContent(agentEngine: agentEngine, browserState: browserState)
        }
    }
}
