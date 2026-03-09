import Foundation

/// Stores information about a closed tab for restoration
struct ClosedTabInfo {
    let url: URL?
    let title: String
    let isChatTab: Bool
    let hasConversationStarted: Bool
    let conversationId: UUID
    let closedAt: Date
}

/// Persisted tab data for workspace switching
struct PersistedTab: Codable {
    let id: UUID
    let url: String?
    let title: String
    let isChatTab: Bool
    let hasConversationStarted: Bool
    let conversationId: UUID

    init(id: UUID, url: String?, title: String, isChatTab: Bool, hasConversationStarted: Bool, conversationId: UUID) {
        self.id = id
        self.url = url
        self.title = title
        self.isChatTab = isChatTab
        self.hasConversationStarted = hasConversationStarted
        self.conversationId = conversationId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        isChatTab = try container.decodeIfPresent(Bool.self, forKey: .isChatTab) ?? false
        hasConversationStarted = try container.decodeIfPresent(Bool.self, forKey: .hasConversationStarted) ?? false
        conversationId = try container.decodeIfPresent(UUID.self, forKey: .conversationId) ?? UUID()
    }
}

/// Persisted workspace tab state
struct WorkspaceTabState: Codable {
    let tabData: [PersistedTab]
    let activeTabId: UUID?
}

struct WorkspaceStateStore {
    let saveTabState: @MainActor (WorkspaceTabState, UUID) -> Void
    let getTabState: @MainActor (UUID) -> WorkspaceTabState?
    let clearTabState: @MainActor (UUID) -> Void

    static let shared = WorkspaceStateStore(
        saveTabState: { state, workspaceID in
            WorkspaceManager.shared.saveTabState(state, for: workspaceID)
        },
        getTabState: { workspaceID in
            WorkspaceManager.shared.getTabState(for: workspaceID)
        },
        clearTabState: { workspaceID in
            WorkspaceManager.shared.clearTabState(for: workspaceID)
        }
    )
}

@Observable
class BrowserState: BrowserBridgeProvider {
    /// Returns a BrowserBridge for a specific tab (protocol conformance)
    @MainActor
    func bridge(for tabId: UUID) -> (any BrowserBridge)? {
        return accessibilityBridge(for: tabId)
    }

    var tabs: [Tab] = []
    @ObservationIgnored private var tabsByID: [UUID: Tab] = [:]
    var activeTabId: UUID?

    /// Stack of recently closed tabs (most recent first)
    @ObservationIgnored private var closedTabsHistory: [ClosedTabInfo] = []
    @ObservationIgnored private let maxClosedTabsHistory = 20
    @ObservationIgnored private let workspaceStateStore: WorkspaceStateStore

    /// Current workspace ID being managed
    private(set) var currentWorkspaceId: UUID?

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

    /// Navigate the active tab to a URL (no-op on chat tabs)
    func navigate(to url: URL) {
        guard activeTab?.isChatTab != true else { return }
        activeTab?.load(url.absoluteString)
        persistCurrentWorkspaceState()
    }

    init(workspaceStateStore: WorkspaceStateStore = .shared) {
        self.workspaceStateStore = workspaceStateStore
        addTab()
    }

    // MARK: - Workspace Integration

    /// Saves the current tab state for the given workspace
    @MainActor
    func saveStateForWorkspace(_ workspaceId: UUID) {
        workspaceStateStore.saveTabState(makeWorkspaceTabState(), workspaceId)
    }

    /// Loads tabs for a workspace, restoring from saved state
    @MainActor
    func loadStateForWorkspace(_ workspaceId: UUID) {
        // Save current workspace state before switching
        if let currentId = currentWorkspaceId, currentId != workspaceId {
            saveStateForWorkspace(currentId)
        }

        currentWorkspaceId = workspaceId

        if let state = workspaceStateStore.getTabState(workspaceId), !state.tabData.isEmpty {
            restoreTabs(from: state)
        } else {
            // No saved state - create a fresh tab for this workspace
            clearAllTabs()
            addTab()
        }
    }

    /// Clears the cached state for a workspace (e.g., when workspace is deleted)
    @MainActor
    func clearStateForWorkspace(_ workspaceId: UUID) {
        workspaceStateStore.clearTabState(workspaceId)
    }

    /// Binds this BrowserState to a workspace manager for automatic syncing
    @MainActor
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
        persistCurrentWorkspaceState()
    }

    /// Add a new tab with a specific URL
    func addTab(withURL url: URL, activate: Bool = true) {
        let tab = Tab()
        tabs.append(tab)
        tabsByID[tab.id] = tab
        if activate {
            activeTabId = tab.id
        }
        tab.load(url.absoluteString)
        assertTabIntegrity()
        persistCurrentWorkspaceState()
    }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1 else { return }

        if let index = tabs.firstIndex(where: { $0.id == id }) {
            let tab = tabs[index]

            // Save tab info to history before closing
            let closedInfo = ClosedTabInfo(
                url: tab.url,
                title: tab.title,
                isChatTab: tab.isChatTab,
                hasConversationStarted: tab.hasConversationStarted,
                conversationId: tab.conversationId,
                closedAt: Date()
            )
            closedTabsHistory.insert(closedInfo, at: 0)

            // Trim history if needed
            if closedTabsHistory.count > maxClosedTabsHistory {
                closedTabsHistory.removeLast()
            }

            // Flush pending conversation save and clean up snapshot before removing
            if tab.isChatTab {
                ConversationManager.shared.saveCurrentConversation()
                AgentManager.shared.clearSnapshot(for: tab.conversationId)
            }

            // Clean up WebView resources before removing
            tab.cleanup()

            // Clean up cached screenshot
            Task { @MainActor in
                TabScreenshotManager.shared.removeScreenshot(for: id)
            }

            tabs.remove(at: index)
            tabsByID.removeValue(forKey: id)

            if activeTabId == id {
                // Select adjacent tab
                let newIndex = min(index, tabs.count - 1)
                activeTabId = tabs[newIndex].id
            }

            assertTabIntegrity()
            persistCurrentWorkspaceState()
        }
    }

    func closeActiveTab() {
        if let id = activeTabId {
            closeTab(id)
        }
    }

    func rebuildAllWebViewsForConfigurationChange() {
        for tab in tabs {
            tab.rebuildWebViewForConfigurationChange()
        }
    }

    func selectTab(_ id: UUID) {
        captureScreenshotOfActiveTab()
        activeTabId = id
        persistCurrentWorkspaceState()
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
        captureScreenshotOfActiveTab()
        activeTabId = tabs[targetIndex].id
        persistCurrentWorkspaceState()
    }

    /// Select the previous tab (wraps around)
    func selectPreviousTab() {
        guard let currentIndex = activeTabIndex, !tabs.isEmpty else { return }
        captureScreenshotOfActiveTab()
        let newIndex = currentIndex > 0 ? currentIndex - 1 : tabs.count - 1
        activeTabId = tabs[newIndex].id
        persistCurrentWorkspaceState()
    }

    /// Select the next tab (wraps around)
    func selectNextTab() {
        guard let currentIndex = activeTabIndex, !tabs.isEmpty else { return }
        captureScreenshotOfActiveTab()
        let newIndex = currentIndex < tabs.count - 1 ? currentIndex + 1 : 0
        activeTabId = tabs[newIndex].id
        persistCurrentWorkspaceState()
    }

    /// Reopen the most recently closed tab
    /// Returns true if a tab was reopened
    @discardableResult
    func reopenLastClosedTab() -> Bool {
        guard let closedInfo = closedTabsHistory.first else { return false }
        closedTabsHistory.removeFirst()

        let tab = Tab(
            title: closedInfo.title,
            isChatTab: closedInfo.isChatTab,
            hasConversationStarted: closedInfo.hasConversationStarted,
            conversationId: closedInfo.conversationId
        )
        tabs.append(tab)
        tabsByID[tab.id] = tab
        activeTabId = tab.id

        if let url = closedInfo.url {
            tab.load(url.absoluteString)
        }

        assertTabIntegrity()
        persistCurrentWorkspaceState()
        return true
    }

    /// Check if there are any closed tabs that can be reopened
    var canReopenClosedTab: Bool {
        !closedTabsHistory.isEmpty
    }

    /// Captures a screenshot of the currently active tab before switching away
    private func captureScreenshotOfActiveTab() {
        guard let tab = activeTab else { return }
        let captureTab = tab
        Task { @MainActor in
            await TabScreenshotManager.shared.captureScreenshot(for: captureTab)
        }
    }

    private func makeWorkspaceTabState() -> WorkspaceTabState {
        let persistedTabs = tabs.map { tab in
            PersistedTab(
                id: tab.id,
                url: tab.url?.absoluteString,
                title: tab.title,
                isChatTab: tab.isChatTab,
                hasConversationStarted: tab.hasConversationStarted,
                conversationId: tab.conversationId
            )
        }

        return WorkspaceTabState(
            tabData: persistedTabs,
            activeTabId: activeTabId
        )
    }

    private func clearAllTabs() {
        for tab in tabs {
            tab.cleanup()
        }
        tabs.removeAll()
        tabsByID.removeAll()
        activeTabId = nil
    }

    private func restoreTabs(from state: WorkspaceTabState) {
        clearAllTabs()

        let restoredActiveTabId: UUID? = {
            if let activeTabId = state.activeTabId,
               state.tabData.contains(where: { $0.id == activeTabId }) {
                return activeTabId
            }
            return state.tabData.first?.id
        }()

        for persistedTab in state.tabData {
            let tab = Tab(
                id: persistedTab.id,
                title: persistedTab.title,
                isChatTab: persistedTab.isChatTab,
                hasConversationStarted: persistedTab.hasConversationStarted,
                conversationId: persistedTab.conversationId
            )
            tabs.append(tab)
            tabsByID[tab.id] = tab

            if let urlString = persistedTab.url {
                tab.restore(urlString, eagerly: persistedTab.id == restoredActiveTabId)
            }
        }

        if let restoredActiveTabId, tabsByID[restoredActiveTabId] != nil {
            activeTabId = restoredActiveTabId
        } else {
            activeTabId = tabs.first?.id
        }

        assertTabIntegrity()
    }

    private func persistCurrentWorkspaceState() {
        guard let workspaceID = currentWorkspaceId else { return }
        Task { @MainActor in
            self.saveStateForWorkspace(workspaceID)
        }
    }
}
