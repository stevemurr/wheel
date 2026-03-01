import SwiftUI

// MARK: - Panel Subtitle Computed Properties

extension OmniBar {
    var scrapePanelSubtitle: String {
        scrapeManager.panelSubtitle
    }

    var historyPanelSubtitle: String {
        // Single pass to count both tabs and history entries
        var tabCount = 0
        var historyCount = 0
        for suggestion in suggestionsVM.suggestions {
            if suggestion.isOpenTab {
                tabCount += 1
            } else {
                historyCount += 1
            }
        }

        if !omniState.inputText.isEmpty && !suggestionsVM.suggestions.isEmpty {
            var parts: [String] = []
            if tabCount > 0 {
                parts.append("\(tabCount) tab\(tabCount == 1 ? "" : "s")")
            }
            if historyCount > 0 {
                parts.append("\(historyCount) history")
            }
            return parts.joined(separator: ", ")
        }
        return "Tabs & Recent"
    }

    var semanticPanelSubtitle: String {
        if semanticSearchVM.isSearching {
            return "Searching..."
        } else if !semanticSearchVM.results.isEmpty {
            return "\(semanticSearchVM.results.count) results"
        }
        return "\(semanticSearchManager.indexedCount) pages indexed"
    }

    var downloadsPanelSubtitle: String {
        downloadManager.panelSubtitle
    }

    var agentPanelSubtitle: String {
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

    var readingListPanelSubtitle: String {
        if readingListVM.isLoading {
            return "Loading..."
        } else if !readingListVM.items.isEmpty {
            return "\(readingListVM.items.count) saved"
        }
        return ""
    }
}
