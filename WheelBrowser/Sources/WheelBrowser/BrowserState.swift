import Foundation
import Combine

/// Stores information about a closed tab for restoration
struct ClosedTabInfo {
    let url: URL?
    let title: String
    let closedAt: Date
}

class BrowserState: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var activeTabId: UUID?

    /// Stack of recently closed tabs (most recent first)
    private var closedTabsHistory: [ClosedTabInfo] = []
    private let maxClosedTabsHistory = 20

    var activeTab: Tab? {
        tabs.first { $0.id == activeTabId }
    }

    /// Returns the index of the active tab, or nil if no active tab
    var activeTabIndex: Int? {
        tabs.firstIndex { $0.id == activeTabId }
    }

    init() {
        addTab()
    }

    func addTab() {
        let tab = Tab()
        tabs.append(tab)
        activeTabId = tab.id
    }

    /// Add a new tab with a specific URL
    func addTab(withURL url: URL) {
        let tab = Tab()
        tabs.append(tab)
        activeTabId = tab.id
        tab.load(url.absoluteString)
    }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1 else { return }

        if let index = tabs.firstIndex(where: { $0.id == id }) {
            let tab = tabs[index]

            // Save tab info to history before closing
            let closedInfo = ClosedTabInfo(
                url: tab.url,
                title: tab.title,
                closedAt: Date()
            )
            closedTabsHistory.insert(closedInfo, at: 0)

            // Trim history if needed
            if closedTabsHistory.count > maxClosedTabsHistory {
                closedTabsHistory.removeLast()
            }

            tabs.remove(at: index)

            if activeTabId == id {
                // Select adjacent tab
                let newIndex = min(index, tabs.count - 1)
                activeTabId = tabs[newIndex].id
            }
        }
    }

    func closeActiveTab() {
        if let id = activeTabId {
            closeTab(id)
        }
    }

    func selectTab(_ id: UUID) {
        activeTabId = id
    }

    /// Select tab by index (1-based for keyboard shortcuts)
    /// Index 9 always selects the last tab (browser convention)
    func selectTab(atIndex index: Int) {
        guard !tabs.isEmpty else { return }

        let targetIndex: Int
        if index == 9 {
            // Cmd+9 always goes to last tab
            targetIndex = tabs.count - 1
        } else {
            // Convert 1-based to 0-based index
            targetIndex = index - 1
        }

        guard targetIndex >= 0 && targetIndex < tabs.count else { return }
        activeTabId = tabs[targetIndex].id
    }

    /// Select the previous tab (wraps around)
    func selectPreviousTab() {
        guard let currentIndex = activeTabIndex, !tabs.isEmpty else { return }
        let newIndex = currentIndex > 0 ? currentIndex - 1 : tabs.count - 1
        activeTabId = tabs[newIndex].id
    }

    /// Select the next tab (wraps around)
    func selectNextTab() {
        guard let currentIndex = activeTabIndex, !tabs.isEmpty else { return }
        let newIndex = currentIndex < tabs.count - 1 ? currentIndex + 1 : 0
        activeTabId = tabs[newIndex].id
    }

    /// Reopen the most recently closed tab
    /// Returns true if a tab was reopened
    @discardableResult
    func reopenLastClosedTab() -> Bool {
        guard let closedInfo = closedTabsHistory.first else { return false }
        closedTabsHistory.removeFirst()

        let tab = Tab()
        tabs.append(tab)
        activeTabId = tab.id

        if let url = closedInfo.url {
            tab.load(url.absoluteString)
        }

        return true
    }

    /// Check if there are any closed tabs that can be reopened
    var canReopenClosedTab: Bool {
        !closedTabsHistory.isEmpty
    }
}
