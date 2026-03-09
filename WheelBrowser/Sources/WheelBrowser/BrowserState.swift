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

    private var tabModel = BrowserTabModel()
    private var selectionModel = BrowserSelectionModel()

    @ObservationIgnored private let tabCollectionController: TabCollectionController
    @ObservationIgnored private let tabSelectionController: TabSelectionController
    @ObservationIgnored private let browserStateEffects: BrowserStateEffects
    @ObservationIgnored private var workspaceSessionController: WorkspaceSessionController

    var tabs: [Tab] {
        get { tabModel.tabs }
        set { tabModel.tabs = newValue }
    }

    var folders: [TabFolder] {
        get { tabModel.folders }
        set { tabModel.folders = newValue }
    }

    var activeTabId: UUID? {
        get { selectionModel.activeTabId }
        set { selectionModel.activeTabId = newValue }
    }

    var activeFolderId: UUID? {
        get { selectionModel.activeFolderId }
        set { selectionModel.activeFolderId = newValue }
    }

    var selectedTabIDs: Set<UUID> {
        get { selectionModel.selectedTabIDs }
        set { selectionModel.selectedTabIDs = newValue }
    }

    private var tabsByID: [UUID: Tab] {
        get { tabModel.tabsByID }
        set { tabModel.tabsByID = newValue }
    }

    private var closedTabsHistory: [ClosedTabInfo] {
        get { tabModel.closedTabsHistory }
        set { tabModel.closedTabsHistory = newValue }
    }

    private var tabSelectionAnchorId: UUID? {
        get { selectionModel.tabSelectionAnchorId }
        set { selectionModel.tabSelectionAnchorId = newValue }
    }

    private var maxClosedTabsHistory: Int {
        BrowserTabModel.maxClosedTabsHistory
    }

    /// Current workspace ID being managed
    private(set) var currentWorkspaceId: UUID? {
        get { workspaceSessionController.currentWorkspaceId }
        set { workspaceSessionController.currentWorkspaceId = newValue }
    }

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
        tabCollectionController.tab(for: tabId, model: tabModel)
    }

    func folder(for folderId: UUID?) -> TabFolder? {
        tabCollectionController.folder(for: folderId, model: tabModel)
    }

    func tabs(in folderId: UUID?) -> [Tab] {
        tabCollectionController.tabs(in: folderId, model: tabModel)
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
        tabSelectionController.contextActionTabIDs(
            for: contextTabId,
            model: tabModel,
            selection: selectionModel
        )
    }

    /// Navigate the active tab to a URL (no-op on chat tabs)
    func navigate(to url: URL) {
        guard activeTab?.isChatTab != true else { return }
        activeTab?.load(url.absoluteString)
        persistCurrentWorkspaceState()
    }

    init(
        workspaceStateStore: WorkspaceStateStore = .shared,
        tabCollectionController: TabCollectionController = TabCollectionController(),
        tabSelectionController: TabSelectionController = TabSelectionController(),
        browserStateEffects: BrowserStateEffects = BrowserStateEffects()
    ) {
        self.tabCollectionController = tabCollectionController
        self.tabSelectionController = tabSelectionController
        self.browserStateEffects = browserStateEffects
        self.workspaceSessionController = WorkspaceSessionController(workspaceStateStore: workspaceStateStore)
        addTab()
    }

    // MARK: - Workspace Integration

    /// Saves the current tab state for the given workspace
    @MainActor
    func saveStateForWorkspace(_ workspaceId: UUID) {
        workspaceSessionController.saveState(makeWorkspaceTabState(), for: workspaceId)
    }

    /// Loads tabs for a workspace, restoring from saved state
    @MainActor
    func loadStateForWorkspace(_ workspaceId: UUID) {
        if let previousWorkspaceID = workspaceSessionController.bind(to: workspaceId) {
            saveStateForWorkspace(previousWorkspaceID)
        }

        if let state = workspaceSessionController.loadState(for: workspaceId), !state.tabData.isEmpty {
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
        workspaceSessionController.clearState(for: workspaceId)
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
        let tab = tabCollectionController.appendTab(
            folderID: resolvedFolderId,
            model: &tabModel
        )

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
        let tab = tabCollectionController.appendTab(
            url: url,
            folderID: resolvedFolderId,
            loadURLImmediately: true,
            model: &tabModel
        )

        if activate {
            activateTab(tab.id, selectionMode: .replace, followTabFolder: true, captureCurrent: true)
        } else {
            persistCurrentWorkspaceState()
        }

        assertTabIntegrity()
    }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1 else { return }
        guard let removal = tabCollectionController.removeTab(id, from: &tabModel) else { return }
        let tab = removal.tab
        let wasActive = activeTabId == id

        tabCollectionController.pushClosedTab(tab, into: &tabModel)
        browserStateEffects.handleClosing(tab: tab)
        selectedTabIDs.remove(id)
        if tabSelectionAnchorId == id {
            tabSelectionAnchorId = nil
        }

        if wasActive {
            activeTabId = replacementVisibleTabID(afterRemovingAt: removal.index)
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
        let folderID = tabCollectionController.createFolder(name: name, color: color, in: &tabModel)

        let orderedTargetIDs = orderedTabIDs(from: movingTabIDs)
        if orderedTargetIDs.isEmpty {
            activeFolderId = folderID
            activeTabId = resolvedVisibleTabID(preferredTabID: activeTabId)
            setSingleSelection(activeTabId)
        } else {
            applyFolderMembership(for: orderedTargetIDs, folderId: folderID)
            activeFolderId = folderID
            activeTabId = resolvedVisibleTabID(preferredTabID: activeTabId ?? orderedTargetIDs.first)
            ensureActiveTabLoadedIfNeeded()
            if let activeTabId {
                recordLastActiveTab(activeTabId)
            }
            setSingleSelection(activeTabId)
        }

        persistCurrentWorkspaceState()
        return folderID
    }

    func updateFolder(id: UUID, name: String, color: String) {
        tabCollectionController.updateFolder(id: id, name: name, color: color, in: &tabModel)
        persistCurrentWorkspaceState()
    }

    func deleteFolder(_ id: UUID) {
        guard folders.contains(where: { $0.id == id }) else { return }

        captureScreenshotOfActiveTab()
        applyFolderMembership(for: tabs(in: id).map(\.id), folderId: nil)
        tabCollectionController.deleteFolder(id, in: &tabModel)

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
        guard let closedInfo = tabCollectionController.reopenLastClosedTab(in: &tabModel) else { return false }

        let restoredFolderId = validFolderId(closedInfo.folderID)
        let tab = tabCollectionController.appendTab(
            title: closedInfo.title,
            folderID: restoredFolderId,
            isChatTab: closedInfo.isChatTab,
            hasConversationStarted: closedInfo.hasConversationStarted,
            conversationId: closedInfo.conversationId,
            model: &tabModel
        )

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
        browserStateEffects.captureScreenshot(of: activeTab)
    }

    private func activateTab(
        _ id: UUID,
        selectionMode: TabSelectionMode,
        followTabFolder: Bool,
        captureCurrent: Bool
    ) {
        let previousActiveTabId = activeTabId

        if captureCurrent && previousActiveTabId != nil && previousActiveTabId != id {
            captureScreenshotOfActiveTab()
        }

        tabSelectionController.activateTab(
            id,
            selectionMode: selectionMode,
            followTabFolder: followTabFolder,
            model: tabModel,
            selection: &selectionModel,
            validFolderID: { [weak self] folderID in
                guard let self else { return nil }
                return self.validFolderId(folderID)
            }
        )
        ensureActiveTabLoadedIfNeeded()
        recordLastActiveTab(id)

        persistCurrentWorkspaceState()
    }

    private func makeWorkspaceTabState() -> WorkspaceTabState {
        tabCollectionController.makeWorkspaceTabState(
            from: tabModel,
            selection: selectionModel
        )
    }

    private func clearAllTabs() {
        tabCollectionController.clearAllTabs(in: &tabModel)
        activeTabId = nil
        activeFolderId = nil
        selectedTabIDs = []
        tabSelectionAnchorId = nil
    }

    private func restoreTabs(from state: WorkspaceTabState) {
        tabCollectionController.restoreTabs(from: state, in: &tabModel)
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
        tabCollectionController.hydrateFolderMembershipFromRestoredState(in: &tabModel)
    }

    private func synchronizeFolders() {
        tabCollectionController.synchronizeFolders(in: &tabModel)
    }

    private func applyFolderMembership(for tabIDs: [UUID], folderId: UUID?) {
        tabCollectionController.applyFolderMembership(for: tabIDs, folderId: folderId, model: &tabModel)
    }

    private func recordLastActiveTab(_ tabId: UUID) {
        tabCollectionController.recordLastActiveTab(tabId, model: &tabModel)
    }

    private func replacementVisibleTabID(afterRemovingAt index: Int) -> UUID? {
        tabSelectionController.replacementVisibleTabID(afterRemovingAt: index, model: tabModel)
    }

    private func resolvedTabIDForFolderSelection(_ folderId: UUID?, preferredTabID: UUID?) -> UUID? {
        tabSelectionController.resolvedTabIDForFolderSelection(
            folderId,
            preferredTabID: preferredTabID,
            model: tabModel,
            activeFolderId: activeFolderId
        )
    }

    private func resolvedVisibleTabID(preferredTabID: UUID?) -> UUID? {
        tabSelectionController.resolvedVisibleTabID(
            preferredTabID: preferredTabID,
            model: tabModel,
            activeFolderId: activeFolderId
        )
    }

    private func ensureActiveTabLoadedIfNeeded() {
        browserStateEffects.ensureActiveTabLoadedIfNeeded(activeTab)
    }

    private func setSingleSelection(_ tabId: UUID?) {
        tabSelectionController.setSingleSelection(tabId, visibleTabs: visibleTabs, selection: &selectionModel)
    }

    private func sanitizeSelection() {
        tabSelectionController.sanitizeSelection(visibleTabs: visibleTabs, selection: &selectionModel)
    }

    private func orderedTabIDs(from ids: [UUID]) -> [UUID] {
        tabCollectionController.orderedTabIDs(from: ids, model: tabModel)
    }

    private func validFolderId(_ folderId: UUID?) -> UUID? {
        tabCollectionController.validFolderId(folderId, model: tabModel)
    }

    private func persistCurrentWorkspaceState() {
        guard let workspaceID = currentWorkspaceId else { return }
        Task { @MainActor in
            self.saveStateForWorkspace(workspaceID)
        }
    }
}
