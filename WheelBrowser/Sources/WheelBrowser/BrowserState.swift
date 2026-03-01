import Foundation
import Combine

/// Stores information about a closed tab for restoration
struct ClosedTabInfo {
    let url: URL?
    let title: String
    let closedAt: Date
}

/// Persisted tab data for workspace switching
struct PersistedTab: Codable {
    let id: UUID
    let url: String?
    let title: String
}

/// Persisted workspace tab state
struct WorkspaceTabState: Codable {
    let tabData: [PersistedTab]
    let activeTabId: UUID?
}

class BrowserState: ObservableObject, BrowserBridgeProvider {
    /// Returns a BrowserBridge for a specific tab (protocol conformance)
    @MainActor
    func bridge(for tabId: UUID) -> (any BrowserBridge)? {
        return accessibilityBridge(for: tabId)
    }

    @Published var tabs: [Tab] = []
    private var tabsByID: [UUID: Tab] = [:]
    @Published var activeTabId: UUID?

    /// Stack of recently closed tabs (most recent first)
    private var closedTabsHistory: [ClosedTabInfo] = []
    private let maxClosedTabsHistory = 20

    /// Current workspace ID being managed
    private(set) var currentWorkspaceId: UUID?

    /// Cache of tab states per workspace (in-memory for quick switching)
    private var workspaceTabStates: [UUID: WorkspaceTabState] = [:]

    var activeTab: Tab? {
        guard let id = activeTabId else { return nil }
        return tabsByID[id]
    }

    /// Debug-only assertion that `tabs` and `tabsByID` are in sync
    private func assertTabIntegrity() {
        #if DEBUG
        assert(tabs.count == tabsByID.count,
               "Tab integrity violation: tabs.count=\(tabs.count) != tabsByID.count=\(tabsByID.count)")
        for tab in tabs {
            assert(tabsByID[tab.id] != nil,
                   "Tab integrity violation: tab \(tab.id) missing from tabsByID")
        }
        #endif
    }

    /// Returns the index of the active tab, or nil if no active tab
    var activeTabIndex: Int? {
        tabs.firstIndex { $0.id == activeTabId }
    }

    /// Returns the IDs of all current tabs
    var tabIDs: [UUID] {
        tabs.map { $0.id }
    }

    /// Returns an AccessibilityBridge for the active tab's webView
    @MainActor
    var accessibilityBridge: AccessibilityBridge? {
        guard let tab = activeTab else { return nil }
        return AccessibilityBridge(webView: tab.webView)
    }

    /// Returns an AccessibilityBridge for a specific tab's webView
    @MainActor
    func accessibilityBridge(for tabId: UUID) -> AccessibilityBridge? {
        guard let tab = tabsByID[tabId] else { return nil }
        return AccessibilityBridge(webView: tab.webView)
    }

    /// Returns a tab by its ID
    func tab(for tabId: UUID) -> Tab? {
        tabsByID[tabId]
    }

    /// Navigate the active tab to a URL
    func navigate(to url: URL) {
        activeTab?.load(url.absoluteString)
    }

    init() {
        addTab()
    }

    // MARK: - Workspace Integration

    /// Saves the current tab state for the given workspace
    func saveStateForWorkspace(_ workspaceId: UUID) {
        let persistedTabs = tabs.map { tab in
            PersistedTab(
                id: tab.id,
                url: tab.url?.absoluteString,
                title: tab.title
            )
        }

        let state = WorkspaceTabState(
            tabData: persistedTabs,
            activeTabId: activeTabId
        )

        workspaceTabStates[workspaceId] = state
    }

    /// Loads tabs for a workspace, restoring from saved state
    func loadStateForWorkspace(_ workspaceId: UUID) {
        // Save current workspace state before switching
        if let currentId = currentWorkspaceId, currentId != workspaceId {
            saveStateForWorkspace(currentId)
        }

        currentWorkspaceId = workspaceId

        // Check if we have cached state for this workspace
        if let state = workspaceTabStates[workspaceId], !state.tabData.isEmpty {
            // Clean up existing tabs before removing
            for tab in tabs {
                tab.cleanup()
            }
            tabs.removeAll()
            tabsByID.removeAll()

            for persistedTab in state.tabData {
                let tab = Tab()
                tabs.append(tab)
                tabsByID[tab.id] = tab

                if let urlString = persistedTab.url {
                    tab.load(urlString)
                }
            }

            activeTabId = state.activeTabId ?? tabs.first?.id
            assertTabIntegrity()
        } else {
            // No saved state - create a fresh tab for this workspace
            for tab in tabs {
                tab.cleanup()
            }
            tabs.removeAll()
            tabsByID.removeAll()
            addTab()
        }
    }

    /// Clears the cached state for a workspace (e.g., when workspace is deleted)
    func clearStateForWorkspace(_ workspaceId: UUID) {
        workspaceTabStates.removeValue(forKey: workspaceId)
    }

    /// Binds this BrowserState to a workspace manager for automatic syncing
    func bindToWorkspace(_ workspaceId: UUID) {
        if currentWorkspaceId != workspaceId {
            loadStateForWorkspace(workspaceId)
        }
    }

    func addTab() {
        let tab = Tab()
        tabs.append(tab)
        tabsByID[tab.id] = tab
        activeTabId = tab.id
        assertTabIntegrity()
    }

    /// Add a new tab with a specific URL
    func addTab(withURL url: URL) {
        let tab = Tab()
        tabs.append(tab)
        tabsByID[tab.id] = tab
        activeTabId = tab.id
        tab.load(url.absoluteString)
        assertTabIntegrity()
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

            // Clean up WebView resources before removing
            tab.cleanup()

            tabs.remove(at: index)
            tabsByID.removeValue(forKey: id)

            if activeTabId == id {
                // Select adjacent tab
                let newIndex = min(index, tabs.count - 1)
                activeTabId = tabs[newIndex].id
            }

            assertTabIntegrity()
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
        tabsByID[tab.id] = tab
        activeTabId = tab.id

        if let url = closedInfo.url {
            tab.load(url.absoluteString)
        }

        assertTabIntegrity()
        return true
    }

    /// Check if there are any closed tabs that can be reopened
    var canReopenClosedTab: Bool {
        !closedTabsHistory.isEmpty
    }
}
