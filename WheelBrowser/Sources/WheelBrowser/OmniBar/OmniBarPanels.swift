import SwiftUI

// MARK: - Panel Views

extension OmniBar {
    @ViewBuilder
    var panelViews: some View {
        // Suggestions panel - appears above OmniBar when in address mode (shows tabs + history)
        // Only render panels when visible to avoid rendering overhead
        if hasAppeared && isHistoryPanelVisible {
            OmniPanel(
                title: "Go to",
                icon: "magnifyingglass",
                iconColor: .accentColor,
                borderColor: .blue,
                subtitle: historyPanelSubtitle,
                onDismiss: {
                    omniState.dismissHistoryPanel()
                }
            ) {
                HistoryPanelContent(
                    viewModel: suggestionsVM,
                    searchText: omniState.inputText,
                    onSelect: { suggestion in
                        handleSuggestionSelection(suggestion)
                    }
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
            .zIndex(999)
        }

        // Chat panel - appears above OmniBar when in chat mode
        if hasAppeared && isChatPanelVisible {
            OmniPanel(
                title: "Chat",
                icon: "bubble.left.and.bubble.right.fill",
                iconColor: .purple,
                borderColor: .purple,
                subtitle: agentManager.isLoading ? "Thinking..." : nil,
                menuContent: {
                    AnyView(
                        Group {
                            Button("Clear Chat") {
                                agentManager.clearMessages()
                            }
                            Divider()
                            Button("Reset Agent", role: .destructive) {
                                Task { await agentManager.resetAgent() }
                            }
                        }
                    )
                },
                onDismiss: {
                    omniState.dismissChatPanel()
                }
            ) {
                ChatPanelContent(agentManager: agentManager)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
            .zIndex(999)
        }

        // Semantic search panel - appears above OmniBar when in semantic mode
        if hasAppeared && isSemanticPanelVisible {
            OmniPanel(
                title: "Semantic Search",
                icon: "brain.head.profile",
                iconColor: .orange,
                borderColor: .orange,
                subtitle: semanticPanelSubtitle,
                menuContent: {
                    AnyView(
                        Group {
                            Button("Clear Index") {
                                Task { await semanticSearchManager.clearIndex() }
                            }
                        }
                    )
                },
                onDismiss: {
                    omniState.dismissSemanticPanel()
                }
            ) {
                SemanticSearchPanelContent(
                    viewModel: semanticSearchVM,
                    searchManager: semanticSearchManager,
                    searchText: omniState.inputText,
                    onSelect: { result in
                        handleSemanticSelection(result)
                    }
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
            .zIndex(999)
        }

        // Agent panel - appears above OmniBar when in agent mode
        if hasAppeared && isAgentPanelVisible {
            OmniPanel(
                title: "Agent",
                icon: "wand.and.stars",
                iconColor: .green,
                borderColor: .green,
                subtitle: agentPanelSubtitle,
                menuContent: {
                    AnyView(
                        Group {
                            Button("Cancel Task") {
                                agentEngine.cancel()
                            }
                            .disabled(!agentEngine.isRunning)
                            Divider()
                            Button("Clear History") {
                                agentEngine.steps = []
                            }
                            .disabled(agentEngine.steps.isEmpty)
                        }
                    )
                },
                onDismiss: {
                    omniState.dismissAgentPanel()
                }
            ) {
                AgentPanelContent(agentEngine: agentEngine, browserState: browserState)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
            .zIndex(999)
        }

        // Reading list panel - appears above OmniBar when in reading list mode
        if hasAppeared && isReadingListPanelVisible {
            OmniPanel(
                title: "Reading List",
                icon: "bookmark.fill",
                iconColor: .pink,
                borderColor: .pink,
                subtitle: readingListPanelSubtitle,
                onDismiss: {
                    omniState.dismissReadingListPanel()
                }
            ) {
                ReadingListPanelContent(
                    viewModel: readingListVM,
                    searchText: omniState.inputText,
                    onSelect: { item in
                        handleReadingListSelection(item)
                    }
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
            .zIndex(999)
        }

        // Downloads panel - appears above OmniBar when downloads are active
        if hasAppeared && downloadManager.showDownloadsPanel {
            OmniPanel(
                title: "Downloads",
                icon: "arrow.down.circle.fill",
                iconColor: .blue,
                borderColor: .blue,
                subtitle: downloadsPanelSubtitle,
                menuContent: {
                    AnyView(
                        Group {
                            Button("Clear Completed") {
                                downloadManager.clearCompleted()
                            }
                            Button("Show in Finder") {
                                if let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    )
                },
                onDismiss: {
                    downloadManager.dismissPanel()
                }
            ) {
                DownloadsPanelContent(manager: downloadManager)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
            .zIndex(999)
        }

        // Scrape panel - appears above OmniBar when in scraping mode or when scrape jobs are active
        if hasAppeared && (omniState.mode == .scraping || scrapeManager.showScrapePanel) {
            OmniPanel(
                title: "Web Scraping",
                icon: "network",
                iconColor: .cyan,
                borderColor: .cyan,
                subtitle: scrapePanelSubtitle,
                menuContent: {
                    AnyView(
                        Group {
                            Button("New Scrape...") {
                                NotificationCenter.default.post(name: .scrapePage, object: nil)
                            }
                            Divider()
                            Button("Clear Completed") {
                                scrapeManager.clearCompleted()
                            }
                        }
                    )
                },
                onDismiss: {
                    scrapeManager.dismissPanel()
                    omniState.dismissScrapingPanel()
                    if omniState.mode == .scraping {
                        omniState.mode = .address
                    }
                }
            ) {
                ScrapePanelContent(manager: scrapeManager)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
            .zIndex(999)
        }
    }
}
