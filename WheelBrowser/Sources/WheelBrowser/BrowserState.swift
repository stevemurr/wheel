import Foundation

enum TabSelectionMode {
    case replace
    case add
    case range
}

/// Stores information about a closed tab for restoration
struct ClosedTabInfo {
    let url: URL?
    let title: String
    let folderID: UUID?
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
    let folderID: UUID?
    let isChatTab: Bool
    let hasConversationStarted: Bool
    let conversationId: UUID

    init(
        id: UUID,
        url: String?,
        title: String,
        folderID: UUID? = nil,
        isChatTab: Bool,
        hasConversationStarted: Bool,
        conversationId: UUID
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.folderID = folderID
        self.isChatTab = isChatTab
        self.hasConversationStarted = hasConversationStarted
        self.conversationId = conversationId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        isChatTab = try container.decodeIfPresent(Bool.self, forKey: .isChatTab) ?? false
        hasConversationStarted = try container.decodeIfPresent(Bool.self, forKey: .hasConversationStarted) ?? false
        conversationId = try container.decodeIfPresent(UUID.self, forKey: .conversationId) ?? UUID()
    }
}

/// Persisted workspace tab state
struct WorkspaceTabState: Codable {
    let tabData: [PersistedTab]
    let activeTabId: UUID?
    let folders: [TabFolder]
    let activeFolderId: UUID?

    init(
        tabData: [PersistedTab],
        activeTabId: UUID?,
        folders: [TabFolder] = [],
        activeFolderId: UUID? = nil
    ) {
        self.tabData = tabData
        self.activeTabId = activeTabId
        self.folders = folders
        self.activeFolderId = activeFolderId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tabData = try container.decode([PersistedTab].self, forKey: .tabData)
        activeTabId = try container.decodeIfPresent(UUID.self, forKey: .activeTabId)
        folders = try container.decodeIfPresent([TabFolder].self, forKey: .folders) ?? []
        activeFolderId = try container.decodeIfPresent(UUID.self, forKey: .activeFolderId)
    }
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
        accessibilityBridge(for: tabId)
    }

    var tabs: [Tab] = []
    var folders: [TabFolder] = []
    var activeTabId: UUID?
    var activeFolderId: UUID?
    var selectedTabIDs: Set<UUID> = []

    @ObservationIgnored private var tabsByID: [UUID: Tab] = [:]
    @ObservationIgnored private var closedTabsHistory: [ClosedTabInfo] = []
    @ObservationIgnored private let maxClosedTabsHistory = 20
    @ObservationIgnored private let workspaceStateStore: WorkspaceStateStore
    @ObservationIgnored private var tabSelectionAnchorId: UUID?

    /// Current workspace ID being managed
    private(set) var currentWorkspaceId: UUID?

    var activeTab: Tab? {
        guard let id = activeTabId else { return nil }
        return tabsByID[id]
    }

    var activeFolder: TabFolder? {
        folder(for: activeFolderId)
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

    /// Returns the index of the active tab in the global tab order, or nil if no active tab
    var activeTabIndex: Int? {
        tabs.firstIndex { $0.id == activeTabId }
    }

    /// Returns the index of the active tab within the tab strip, or nil if no active tab
    var activeVisibleTabIndex: Int? {
        visibleTabs.firstIndex { $0.id == activeTabId }
    }

    /// Returns the IDs of all current tabs
    var tabIDs: [UUID] {
        tabs.map(\.id)
    }

    var visibleTabs: [Tab] {
        tabs
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

    func folder(for folderId: UUID?) -> TabFolder? {
        guard let folderId else { return nil }
        return folders.first { $0.id == folderId }
    }

    func tabs(in folderId: UUID?) -> [Tab] {
        tabs.filter { $0.folderID == folderId }
    }

    func tabCount(in folderId: UUID?) -> Int {
        tabs(in: folderId).count
    }

    func previewTabs(in folderId: UUID?, limit: Int = 3) -> [Tab] {
        Array(tabs(in: folderId).prefix(limit))
    }

    func isTabSelected(_ tabId: UUID) -> Bool {
        selectedTabIDs.contains(tabId)
    }

    func contextActionTabIDs(for contextTabId: UUID) -> [UUID] {
        let visibleIDs = Set(visibleTabs.map(\.id))
        if selectedTabIDs.contains(contextTabId) {
            let selectedVisible = tabs
                .filter { visibleIDs.contains($0.id) && selectedTabIDs.contains($0.id) }
                .map(\.id)
            if !selectedVisible.isEmpty {
                return selectedVisible
            }
        }
        return [contextTabId]
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
        if let currentId = currentWorkspaceId, currentId != workspaceId {
            saveStateForWorkspace(currentId)
        }

        currentWorkspaceId = workspaceId

        if let state = workspaceStateStore.getTabState(workspaceId), !state.tabData.isEmpty {
            restoreTabs(from: state)
        } else {
            clearAllTabs()
            folders = []
            activeFolderId = nil
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
        addTab(in: activeFolderId)
    }

    func addTab(in folderId: UUID?, activate: Bool = true) {
        let resolvedFolderId = validFolderId(folderId)
        let tab = Tab(folderID: resolvedFolderId)
        tabs.append(tab)
        tabsByID[tab.id] = tab
        synchronizeFolders()

        if activate {
            activateTab(tab.id, selectionMode: .replace, followTabFolder: true, captureCurrent: true)
        } else {
            persistCurrentWorkspaceState()
        }

        assertTabIntegrity()
    }

    /// Add a new tab with a specific URL
    func addTab(withURL url: URL, activate: Bool = true) {
        addTab(withURL: url, in: activeFolderId, activate: activate)
    }

    func addTab(withURL url: URL, in folderId: UUID?, activate: Bool = true) {
        let resolvedFolderId = validFolderId(folderId)
        let tab = Tab(folderID: resolvedFolderId)
        tabs.append(tab)
        tabsByID[tab.id] = tab
        tab.load(url.absoluteString)
        synchronizeFolders()

        if activate {
            activateTab(tab.id, selectionMode: .replace, followTabFolder: true, captureCurrent: true)
        } else {
            persistCurrentWorkspaceState()
        }

        assertTabIntegrity()
    }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1 else { return }
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        let tab = tabs[index]
        let wasActive = activeTabId == id

        let closedInfo = ClosedTabInfo(
            url: tab.url,
            title: tab.title,
            folderID: tab.folderID,
            isChatTab: tab.isChatTab,
            hasConversationStarted: tab.hasConversationStarted,
            conversationId: tab.conversationId,
            closedAt: Date()
        )
        closedTabsHistory.insert(closedInfo, at: 0)

        if closedTabsHistory.count > maxClosedTabsHistory {
            closedTabsHistory.removeLast()
        }

        if tab.isChatTab {
            ConversationManager.shared.saveCurrentConversation()
            AgentManager.shared.clearSnapshot(for: tab.conversationId)
        }

        tab.cleanup()

        Task { @MainActor in
            TabScreenshotManager.shared.removeScreenshot(for: id)
        }

        tabs.remove(at: index)
        tabsByID.removeValue(forKey: id)
        selectedTabIDs.remove(id)
        if tabSelectionAnchorId == id {
            tabSelectionAnchorId = nil
        }

        synchronizeFolders()

        if wasActive {
            activeTabId = replacementVisibleTabID(afterRemovingAt: index)
            ensureActiveTabLoadedIfNeeded()
            if let activeTabId {
                recordLastActiveTab(activeTabId)
            }
            setSingleSelection(activeTabId)
        } else {
            sanitizeSelection()
        }

        assertTabIntegrity()
        persistCurrentWorkspaceState()
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

    func selectFolder(_ folderId: UUID?) {
        let resolvedFolderId = validFolderId(folderId)
        if resolvedFolderId != activeFolderId {
            captureScreenshotOfActiveTab()
        }

        activeFolderId = resolvedFolderId
        activeTabId = resolvedTabIDForFolderSelection(resolvedFolderId, preferredTabID: activeTabId)
        ensureActiveTabLoadedIfNeeded()
        if let activeTabId {
            recordLastActiveTab(activeTabId)
        }
        setSingleSelection(activeTabId)
        persistCurrentWorkspaceState()
    }

    @discardableResult
    func createFolder(name: String, color: String, movingTabIDs: [UUID] = []) -> UUID {
        let folder = TabFolder(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? TabFolder.defaultName(for: folders)
                : name.trimmingCharacters(in: .whitespacesAndNewlines),
            color: color
        )
        folders.append(folder)

        let orderedTargetIDs = orderedTabIDs(from: movingTabIDs)
        if orderedTargetIDs.isEmpty {
            activeFolderId = folder.id
            activeTabId = resolvedVisibleTabID(preferredTabID: activeTabId)
            setSingleSelection(activeTabId)
        } else {
            applyFolderMembership(for: orderedTargetIDs, folderId: folder.id)
            activeFolderId = folder.id
            activeTabId = resolvedVisibleTabID(preferredTabID: activeTabId ?? orderedTargetIDs.first)
            ensureActiveTabLoadedIfNeeded()
            if let activeTabId {
                recordLastActiveTab(activeTabId)
            }
            setSingleSelection(activeTabId)
        }

        persistCurrentWorkspaceState()
        return folder.id
    }

    func updateFolder(id: UUID, name: String, color: String) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        folders[index].name = trimmedName.isEmpty ? folders[index].name : trimmedName
        folders[index].color = color
        folders[index].touch()
        persistCurrentWorkspaceState()
    }

    func deleteFolder(_ id: UUID) {
        guard folders.contains(where: { $0.id == id }) else { return }

        captureScreenshotOfActiveTab()
        applyFolderMembership(for: tabs(in: id).map(\.id), folderId: nil)
        folders.removeAll { $0.id == id }

        if activeFolderId == id {
            activeFolderId = nil
        }

        activeTabId = resolvedVisibleTabID(preferredTabID: activeTabId)
        ensureActiveTabLoadedIfNeeded()
        if let activeTabId {
            recordLastActiveTab(activeTabId)
        }
        setSingleSelection(activeTabId)
        persistCurrentWorkspaceState()
    }

    func moveTabs(_ tabIDs: [UUID], toFolder folderId: UUID?) {
        let orderedTargetIDs = orderedTabIDs(from: tabIDs)
        guard !orderedTargetIDs.isEmpty else { return }

        applyFolderMembership(for: orderedTargetIDs, folderId: validFolderId(folderId))
        activeTabId = resolvedVisibleTabID(preferredTabID: activeTabId)
        ensureActiveTabLoadedIfNeeded()
        if let activeTabId {
            recordLastActiveTab(activeTabId)
        }
        setSingleSelection(activeTabId)
        persistCurrentWorkspaceState()
    }

    func removeTabsFromFolders(_ tabIDs: [UUID]) {
        moveTabs(tabIDs, toFolder: nil)
    }

    func handleTabActivation(_ id: UUID, selectionMode: TabSelectionMode) {
        activateTab(id, selectionMode: selectionMode, followTabFolder: true, captureCurrent: activeTabId != id)
    }

    func selectTab(_ id: UUID) {
        activateTab(id, selectionMode: .replace, followTabFolder: true, captureCurrent: activeTabId != id)
    }

    /// Select tab by index (1-based for keyboard shortcuts)
    /// Index 9 always selects the last visible tab (browser convention)
    func selectTab(atIndex index: Int) {
        let scopedTabs = visibleTabs
        guard !scopedTabs.isEmpty else { return }

        let targetIndex: Int
        if index == 9 {
            targetIndex = scopedTabs.count - 1
        } else {
            targetIndex = index - 1
        }

        guard targetIndex >= 0 && targetIndex < scopedTabs.count else { return }
        selectTab(scopedTabs[targetIndex].id)
    }

    /// Select the previous visible tab (wraps around)
    func selectPreviousTab() {
        let scopedTabs = visibleTabs
        guard let currentIndex = activeVisibleTabIndex, !scopedTabs.isEmpty else { return }
        let newIndex = currentIndex > 0 ? currentIndex - 1 : scopedTabs.count - 1
        selectTab(scopedTabs[newIndex].id)
    }

    /// Select the next visible tab (wraps around)
    func selectNextTab() {
        let scopedTabs = visibleTabs
        guard let currentIndex = activeVisibleTabIndex, !scopedTabs.isEmpty else { return }
        let newIndex = currentIndex < scopedTabs.count - 1 ? currentIndex + 1 : 0
        selectTab(scopedTabs[newIndex].id)
    }

    /// Reopen the most recently closed tab
    /// Returns true if a tab was reopened
    @discardableResult
    func reopenLastClosedTab() -> Bool {
        guard let closedInfo = closedTabsHistory.first else { return false }
        closedTabsHistory.removeFirst()

        let restoredFolderId = validFolderId(closedInfo.folderID)
        let tab = Tab(
            title: closedInfo.title,
            folderID: restoredFolderId,
            isChatTab: closedInfo.isChatTab,
            hasConversationStarted: closedInfo.hasConversationStarted,
            conversationId: closedInfo.conversationId
        )
        tabs.append(tab)
        tabsByID[tab.id] = tab
        synchronizeFolders()

        if let url = closedInfo.url {
            tab.load(url.absoluteString)
        }

        activateTab(tab.id, selectionMode: .replace, followTabFolder: true, captureCurrent: true)

        assertTabIntegrity()
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

    private func activateTab(
        _ id: UUID,
        selectionMode: TabSelectionMode,
        followTabFolder: Bool,
        captureCurrent: Bool
    ) {
        guard let tab = tabsByID[id] else { return }
        let previousActiveTabId = activeTabId
        let previousAnchor = tabSelectionAnchorId ?? activeTabId ?? id

        if captureCurrent && previousActiveTabId != nil && previousActiveTabId != id {
            captureScreenshotOfActiveTab()
        }

        if followTabFolder {
            activeFolderId = validFolderId(tab.folderID)
        }

        activeTabId = id
        ensureActiveTabLoadedIfNeeded()
        recordLastActiveTab(id)

        switch selectionMode {
        case .replace:
            setSingleSelection(id)
        case .add:
            var newSelection = Set(orderedTabIDs(from: Array(selectedTabIDs)))
            if newSelection.contains(id) {
                newSelection.remove(id)
            } else {
                newSelection.insert(id)
            }

            let visibleIDSet = Set(visibleTabs.map(\.id))
            newSelection = newSelection.intersection(visibleIDSet)

            if newSelection.isEmpty {
                newSelection.insert(id)
            }

            selectedTabIDs = newSelection
            tabSelectionAnchorId = id
        case .range:
            let orderedVisibleIDs = visibleTabs.map(\.id)
            guard let anchorIndex = orderedVisibleIDs.firstIndex(of: previousAnchor),
                  let selectedIndex = orderedVisibleIDs.firstIndex(of: id) else {
                setSingleSelection(id)
                persistCurrentWorkspaceState()
                return
            }

            let lowerBound = min(anchorIndex, selectedIndex)
            let upperBound = max(anchorIndex, selectedIndex)
            selectedTabIDs = Set(orderedVisibleIDs[lowerBound...upperBound])
            tabSelectionAnchorId = previousAnchor
        }

        persistCurrentWorkspaceState()
    }

    private func makeWorkspaceTabState() -> WorkspaceTabState {
        let persistedTabs = tabs.map { tab in
            PersistedTab(
                id: tab.id,
                url: tab.url?.absoluteString,
                title: tab.title,
                folderID: tab.folderID,
                isChatTab: tab.isChatTab,
                hasConversationStarted: tab.hasConversationStarted,
                conversationId: tab.conversationId
            )
        }

        return WorkspaceTabState(
            tabData: persistedTabs,
            activeTabId: activeTabId,
            folders: folders,
            activeFolderId: activeFolderId
        )
    }

    private func clearAllTabs() {
        for tab in tabs {
            tab.cleanup()
        }
        tabs.removeAll()
        tabsByID.removeAll()
        activeTabId = nil
        selectedTabIDs = []
        tabSelectionAnchorId = nil
    }

    private func restoreTabs(from state: WorkspaceTabState) {
        clearAllTabs()
        folders = state.folders

        for persistedTab in state.tabData {
            let tab = Tab(
                id: persistedTab.id,
                title: persistedTab.title,
                folderID: persistedTab.folderID,
                isChatTab: persistedTab.isChatTab,
                hasConversationStarted: persistedTab.hasConversationStarted,
                conversationId: persistedTab.conversationId
            )
            tabs.append(tab)
            tabsByID[tab.id] = tab

            if let urlString = persistedTab.url {
                tab.restore(urlString, eagerly: false)
            }
        }

        hydrateFolderMembershipFromRestoredState()
        activeFolderId = validFolderId(state.activeFolderId)

        if activeFolderId == nil,
           let restoredActiveTab = state.activeTabId.flatMap({ tabsByID[$0] }) {
            activeFolderId = validFolderId(restoredActiveTab.folderID)
        }

        activeTabId = resolvedVisibleTabID(preferredTabID: state.activeTabId)
        ensureActiveTabLoadedIfNeeded()
        if let activeTabId {
            recordLastActiveTab(activeTabId)
        }
        setSingleSelection(activeTabId)
        assertTabIntegrity()
    }

    private func hydrateFolderMembershipFromRestoredState() {
        let validFolderIDs = Set(folders.map(\.id))
        var fallbackAssignments: [UUID: UUID] = [:]

        for folder in folders {
            for tabID in folder.tabIDs where fallbackAssignments[tabID] == nil {
                fallbackAssignments[tabID] = folder.id
            }
        }

        for tab in tabs {
            if let folderID = tab.folderID, validFolderIDs.contains(folderID) {
                continue
            }
            tab.folderID = fallbackAssignments[tab.id]
        }

        synchronizeFolders()
    }

    private func synchronizeFolders() {
        for index in folders.indices {
            let folderId = folders[index].id
            let orderedTabIDs = tabs.filter { $0.folderID == folderId }.map(\.id)
            let hadChanges = folders[index].tabIDs != orderedTabIDs

            folders[index].tabIDs = orderedTabIDs

            if let lastActiveTabID = folders[index].lastActiveTabID,
               !orderedTabIDs.contains(lastActiveTabID) {
                folders[index].lastActiveTabID = orderedTabIDs.first
            }

            if hadChanges {
                folders[index].touch()
            }
        }
    }

    private func applyFolderMembership(for tabIDs: [UUID], folderId: UUID?) {
        for tabID in tabIDs {
            tabsByID[tabID]?.folderID = folderId
        }
        synchronizeFolders()
    }

    private func recordLastActiveTab(_ tabId: UUID) {
        guard let folderId = tabsByID[tabId]?.folderID,
              let index = folders.firstIndex(where: { $0.id == folderId }) else {
            return
        }

        if folders[index].lastActiveTabID != tabId {
            folders[index].lastActiveTabID = tabId
            folders[index].touch()
        }
    }

    private func replacementVisibleTabID(afterRemovingAt index: Int) -> UUID? {
        guard !tabs.isEmpty else { return nil }

        if index < tabs.count {
            let nextTab = tabs[index]
            return nextTab.id
        }

        let safeUpperBound = min(index, tabs.count)
        if safeUpperBound > 0 {
            return tabs[safeUpperBound - 1].id
        }

        return nil
    }

    private func resolvedTabIDForFolderSelection(_ folderId: UUID?, preferredTabID: UUID?) -> UUID? {
        let scopedTabs = tabs(in: folderId)

        if let preferredTabID,
           scopedTabs.contains(where: { $0.id == preferredTabID }) {
            return preferredTabID
        }

        if let folderId,
           let folder = folder(for: folderId),
           let lastActiveTabID = folder.lastActiveTabID,
           scopedTabs.contains(where: { $0.id == lastActiveTabID }) {
            return lastActiveTabID
        }

        if folderId == nil,
           let preferredTabID,
           tabsByID[preferredTabID]?.folderID == nil {
            return preferredTabID
        }

        if let firstTabID = scopedTabs.first?.id {
            return firstTabID
        }

        return resolvedVisibleTabID(preferredTabID: preferredTabID)
    }

    private func resolvedVisibleTabID(preferredTabID: UUID?) -> UUID? {
        let scopedTabs = visibleTabs
        guard !scopedTabs.isEmpty else { return nil }

        if let preferredTabID,
           scopedTabs.contains(where: { $0.id == preferredTabID }) {
            return preferredTabID
        }

        if let folderId = activeFolderId,
           let folder = folder(for: folderId),
           let lastActiveTabID = folder.lastActiveTabID,
           scopedTabs.contains(where: { $0.id == lastActiveTabID }) {
            return lastActiveTabID
        }

        return scopedTabs.first?.id
    }

    private func ensureActiveTabLoadedIfNeeded() {
        guard let tab = activeTab,
              let url = tab.url,
              !tab.hasWebView else { return }
        tab.restore(url.absoluteString, eagerly: true)
    }

    private func setSingleSelection(_ tabId: UUID?) {
        if let tabId,
           visibleTabs.contains(where: { $0.id == tabId }) {
            selectedTabIDs = [tabId]
            tabSelectionAnchorId = tabId
        } else {
            selectedTabIDs = []
            tabSelectionAnchorId = nil
        }
    }

    private func sanitizeSelection() {
        let visibleIDSet = Set(visibleTabs.map(\.id))
        selectedTabIDs = selectedTabIDs.intersection(visibleIDSet)

        if let anchorId = tabSelectionAnchorId,
           !visibleIDSet.contains(anchorId) {
            tabSelectionAnchorId = activeTabId
        }

        if selectedTabIDs.isEmpty {
            setSingleSelection(activeTabId)
        }
    }

    private func orderedTabIDs(from ids: [UUID]) -> [UUID] {
        let uniqueIDs = Set(ids)
        return tabs.map(\.id).filter { uniqueIDs.contains($0) }
    }

    private func validFolderId(_ folderId: UUID?) -> UUID? {
        guard let folderId else { return nil }
        return folders.contains(where: { $0.id == folderId }) ? folderId : nil
    }

    private func persistCurrentWorkspaceState() {
        guard let workspaceID = currentWorkspaceId else { return }
        Task { @MainActor in
            self.saveStateForWorkspace(workspaceID)
        }
    }
}
