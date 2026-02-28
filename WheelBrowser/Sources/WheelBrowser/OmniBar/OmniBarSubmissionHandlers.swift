import SwiftUI

// MARK: - Submission Handlers

extension OmniBar {
    func handleSubmit() {
        switch omniState.mode {
        case .address:
            submitAddress()
        case .chat:
            submitChat()
        case .semantic:
            submitSemantic()
        case .agent:
            submitAgent()
        case .readingList:
            submitReadingList()
        case .scraping:
            break // Scraping mode has no text input submission
        }
    }

    func submitAddress() {
        if let selected = suggestionsVM.selectedSuggestion {
            handleSuggestionSelection(selected)
            return
        }
        tab.load(omniState.inputText)
        isInputFocused = false
        suggestionsVM.hide()
        omniState.dismissHistoryPanel()
    }

    func handleSuggestionSelection(_ suggestion: Suggestion) {
        switch suggestion {
        case .openTab(let tab, _, _, _):
            browserState.selectTab(tab.id)
            isInputFocused = false
            omniState.dismissHistoryPanel()
            suggestionsVM.hide()
            omniState.inputText = tab.url?.absoluteString ?? ""

        case .history(let entry, _, _, _):
            omniState.inputText = entry.url
            self.tab.load(entry.url)
            isInputFocused = false
            omniState.dismissHistoryPanel()
            suggestionsVM.hide()
        }
    }

    func submitChat() {
        let content = omniState.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        // Capture mentions before clearing
        let currentMentions = omniState.mentions

        let hasHistory = currentMentions.contains { if case .history = $0 { return true } else { return false } }
        let hasWeb = currentMentions.contains { if case .web = $0 { return true } else { return false } }
        let hasReadingList = currentMentions.contains { if case .readingList = $0 { return true } else { return false } }

        omniState.inputText = ""
        isSending = true

        omniState.openChatPanel()

        Task {
            // Extract content from all mentioned sources
            var pageContexts: [PageContext] = []

            // @history — fast local fuzzy search on BrowsingHistory
            if hasHistory {
                let historyResults = BrowsingHistory.shared.search(query: content, limit: 5)
                for entry in historyResults {
                    let ctx = PageContext(
                        url: entry.url,
                        title: entry.title,
                        textContent: """
                        [From History]
                        URL: \(entry.url)
                        Title: \(entry.title)
                        """
                    )
                    pageContexts.append(ctx)
                }
            }

            // @web — semantic search across all DIndex categories (no filter)
            if hasWeb {
                let webResults = await SemanticSearchManagerV2.shared.search(query: content, limit: 5)
                for result in webResults {
                    let ctx = PageContext(
                        url: result.page.url,
                        title: result.page.title,
                        textContent: """
                        [From Web]
                        URL: \(result.page.url)
                        \(result.page.snippet)
                        """
                    )
                    pageContexts.append(ctx)
                }
            }

            // @readingList — category-filtered semantic search (skip if @web already covers it)
            if hasReadingList && !hasWeb {
                let rlResults = await SemanticSearchManagerV2.shared.searchWithCategories(
                    query: content,
                    categories: [.readingList],
                    limit: 5
                )
                for result in rlResults {
                    let ctx = PageContext(
                        url: result.page.url,
                        title: result.page.title,
                        textContent: """
                        [From Reading List]
                        URL: \(result.page.url)
                        \(result.page.snippet)
                        """
                    )
                    pageContexts.append(ctx)
                }
            }

            for mention in currentMentions {
                switch mention {
                case .currentPage:
                    if let context = await contentExtractor.extractContent(from: tab) {
                        pageContexts.append(context)
                    }

                case .tab(let tabId, _, _):
                    // Find the tab and extract its content
                    if let mentionedTab = browserState.tabs.first(where: { $0.id == tabId }) {
                        if let context = await contentExtractor.extractContent(from: mentionedTab) {
                            pageContexts.append(context)
                        }
                    }

                case .overlay(let overlayId, let title, let url):
                    // For overlay windows, include URL and title as context
                    // The overlay content can be accessed via the OverlayWindowManager
                    let overlayContext = PageContext(
                        url: url,
                        title: title,
                        textContent: "[Content from mini window - URL: \(url)]"
                    )
                    pageContexts.append(overlayContext)

                case .semanticResult(_, _, let url):
                    // For semantic results, we include the URL as context
                    // The actual content would need to be fetched, but for now we provide URL info
                    let semanticContext = PageContext(
                        url: url,
                        title: mention.displayTitle,
                        textContent: "[Content from browsing history - URL: \(url)]"
                    )
                    pageContexts.append(semanticContext)

                case .history, .web, .readingList:
                    // Already handled above via category filtering
                    break

                case .domain:
                    // Domain filtering could be added as URL prefix filter in future
                    break
                }
            }

            await agentManager.sendMessage(content, pageContexts: pageContexts)
            isSending = false

            // Reset mentions to default after sending (exclude current page if on new tab)
            omniState.resetMentions(includeCurrentPage: tab.url != nil)
        }
    }

    func submitSemantic() {
        if let selected = semanticSearchVM.selectedResult {
            handleSemanticSelection(selected)
        }
    }

    func handleSemanticSelection(_ result: SemanticSearchResult) {
        tab.load(result.page.url)
        isInputFocused = false
        omniState.dismissSemanticPanel()
        semanticSearchVM.clear()
        omniState.inputText = ""
    }

    func handleReadingListSelection(_ item: SavedPageRecord) {
        tab.load(item.url.absoluteString)
        isInputFocused = false
        omniState.dismissReadingListPanel()
        readingListVM.clear()
        omniState.inputText = ""
    }

    func submitAgent() {
        let task = omniState.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }

        omniState.inputText = ""
        omniState.openAgentPanel()

        Task {
            _ = await agentEngine.run(task: task)
        }
    }

    func submitReadingList() {
        if let selected = readingListVM.selectedItem {
            handleReadingListSelection(selected)
        }
    }
}
