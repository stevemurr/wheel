import SwiftUI

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

struct SelectableResultsPanel<Item: Identifiable, Row: View, EmptyState: View>: View {
    let items: [Item]
    let selectedIndex: Int
    let emptyState: () -> EmptyState
    let row: (Int, Item) -> Row

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: true) {
                LazyVStack(spacing: 2) {
                    if items.isEmpty {
                        emptyState()
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(index, item)
                                .id(item.id)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .onChange(of: selectedIndex) { _, newIndex in
                if newIndex >= 0 && newIndex < items.count {
                    let selectedID = items[newIndex].id
                    withAnimation(AppAnimation.quickOut) {
                        proxy.scrollTo(selectedID, anchor: .center)
                    }
                }
            }
        }
    }
}

extension OmniBar {
    @ViewBuilder
    var panelViews: some View {
        ForEach(Array(featureModel.orderedModuleIDs), id: \.rawValue) { moduleID in
            if let provider = featureModel.registry.module(for: moduleID) as? any OmniBarPanelProviding,
               let descriptor = provider.panelDescriptor(in: featureModel) {
                RenderedOmniPanel(descriptor: descriptor) {
                    featureModel.dismissVisiblePanel()
                }
                .panelWrapper()
            }
        }

        DownloadsOmniPanel()
    }
}

private struct RenderedOmniPanel: View {
    let descriptor: OmniBarPanelDescriptor
    let onDismiss: () -> Void

    var body: some View {
        if let menuContent = descriptor.menuContent {
            OmniPanel(
                title: descriptor.title,
                icon: descriptor.icon,
                iconColor: descriptor.iconColor,
                borderColor: descriptor.borderColor,
                subtitle: descriptor.subtitle,
                menuContent: { menuContent },
                onDismiss: onDismiss
            ) {
                descriptor.content
            }
        } else {
            OmniPanel(
                title: descriptor.title,
                icon: descriptor.icon,
                iconColor: descriptor.iconColor,
                borderColor: descriptor.borderColor,
                subtitle: descriptor.subtitle,
                onDismiss: onDismiss
            ) {
                descriptor.content
            }
        }
    }
}

struct HistoryPanelContent: View {
    var viewModel: SuggestionsViewModel
    let searchText: String
    let onSelect: (Suggestion) -> Void

    var body: some View {
        SelectableResultsPanel(
            items: viewModel.suggestions,
            selectedIndex: viewModel.selectedIndex,
            emptyState: {
                Group {
                    if searchText.isEmpty {
                        OmniPanelEmptyState(
                            icon: "clock",
                            title: "No browsing history",
                            subtitle: "Pages you visit will appear here"
                        )
                        .padding(.top, 30)
                    } else {
                        OmniPanelEmptyState(
                            icon: "magnifyingglass",
                            title: "No matches found",
                            subtitle: "Try a different search term"
                        )
                        .padding(.top, 30)
                    }
                }
            },
            row: { index, suggestion in
                SuggestionRow(
                    suggestion: suggestion,
                    isSelected: index == viewModel.selectedIndex,
                    onSelect: { onSelect(suggestion) }
                )
            }
        )
    }
}

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
}

private struct DownloadsOmniPanel: View {
    private var downloadManager = DownloadManager.shared

    var body: some View {
        if downloadManager.showDownloadsPanel {
            OmniPanel(
                title: "Downloads",
                icon: "arrow.down.circle.fill",
                iconColor: .blue,
                borderColor: .blue,
                subtitle: downloadManager.panelSubtitle,
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
