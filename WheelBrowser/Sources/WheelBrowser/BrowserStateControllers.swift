import Foundation

struct BrowserTabModel {
    static let maxClosedTabsHistory = 20

    var tabs: [Tab] = []
    var tabsByID: [UUID: Tab] = [:]
    var folders: [TabFolder] = []
    var closedTabsHistory: [ClosedTabInfo] = []
}

struct BrowserSelectionModel {
    var activeTabId: UUID?
    var activeFolderId: UUID?
    var selectedTabIDs: Set<UUID> = []
    var tabSelectionAnchorId: UUID?
}

enum TabInsertionPlacement: Equatable {
    case before(UUID)
    case after(UUID)
    case end
}

struct TabCollectionController {
    @discardableResult
    func appendTab(
        id: UUID = UUID(),
        title: String = "New Tab",
        url: URL? = nil,
        folderID: UUID? = nil,
        isChatTab: Bool = false,
        hasConversationStarted: Bool = false,
        conversationId: UUID = UUID(),
        loadURLImmediately: Bool = false,
        shouldSynchronizeFolders: Bool = true,
        model: inout BrowserTabModel
    ) -> Tab {
        let restoredChatState = BrowserExperience.aiChatEnabled && isChatTab
        let tab = Tab(
            id: id,
            title: title,
            url: url,
            folderID: folderID,
            isChatTab: restoredChatState,
            hasConversationStarted: hasConversationStarted,
            conversationId: conversationId
        )
        model.tabs.append(tab)
        model.tabsByID[tab.id] = tab

        if let url, loadURLImmediately {
            tab.load(url.absoluteString)
        }

        if shouldSynchronizeFolders {
            synchronizeFolders(in: &model)
        }
        return tab
    }

    func removeTab(_ id: UUID, from model: inout BrowserTabModel) -> (tab: Tab, index: Int)? {
        guard let index = model.tabs.firstIndex(where: { $0.id == id }) else { return nil }
        let tab = model.tabs.remove(at: index)
        model.tabsByID.removeValue(forKey: id)
        synchronizeFolders(in: &model)
        return (tab, index)
    }

    func pushClosedTab(_ tab: Tab, into model: inout BrowserTabModel) {
        let closedInfo = ClosedTabInfo(
            url: tab.url,
            title: tab.title,
            folderID: tab.folderID,
            isChatTab: tab.isChatTab,
            hasConversationStarted: tab.hasConversationStarted,
            conversationId: tab.conversationId,
            closedAt: Date()
        )
        model.closedTabsHistory.insert(closedInfo, at: 0)
        if model.closedTabsHistory.count > BrowserTabModel.maxClosedTabsHistory {
            model.closedTabsHistory.removeLast()
        }
    }

    func reopenLastClosedTab(in model: inout BrowserTabModel) -> ClosedTabInfo? {
        guard let closedInfo = model.closedTabsHistory.first else { return nil }
        model.closedTabsHistory.removeFirst()
        return closedInfo
    }

    func clearAllTabs(in model: inout BrowserTabModel) {
        for tab in model.tabs {
            tab.cleanup()
        }
        model.tabs.removeAll()
        model.tabsByID.removeAll()
    }

    @discardableResult
    func createFolder(name: String, color: String, in model: inout BrowserTabModel) -> UUID {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = TabFolder(
            name: trimmedName.isEmpty
                ? TabFolder.defaultName(for: model.folders)
                : trimmedName,
            color: color
        )
        model.folders.append(folder)
        return folder.id
    }

    func updateFolder(id: UUID, name: String, color: String, in model: inout BrowserTabModel) {
        guard let index = model.folders.firstIndex(where: { $0.id == id }) else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        model.folders[index].name = trimmedName.isEmpty ? model.folders[index].name : trimmedName
        model.folders[index].color = color
        model.folders[index].touch()
    }

    func deleteFolder(_ id: UUID, in model: inout BrowserTabModel) {
        model.folders.removeAll { $0.id == id }
    }

    func restoreTabs(from state: WorkspaceTabState, in model: inout BrowserTabModel) {
        clearAllTabs(in: &model)
        model.folders = state.folders

        for persistedTab in state.tabData {
            let tab = appendTab(
                id: persistedTab.id,
                title: persistedTab.title,
                folderID: persistedTab.folderID,
                isChatTab: persistedTab.isChatTab,
                hasConversationStarted: persistedTab.hasConversationStarted,
                conversationId: persistedTab.conversationId,
                shouldSynchronizeFolders: false,
                model: &model
            )

            if let urlString = persistedTab.url {
                tab.restore(urlString, eagerly: false)
            }
        }

        hydrateFolderMembershipFromRestoredState(in: &model)
    }

    func makeWorkspaceTabState(
        from model: BrowserTabModel,
        selection: BrowserSelectionModel
    ) -> WorkspaceTabState {
        let persistedTabs = model.tabs.map { tab in
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
            activeTabId: selection.activeTabId,
            folders: model.folders,
            activeFolderId: selection.activeFolderId
        )
    }

    func tabs(in folderId: UUID?, model: BrowserTabModel) -> [Tab] {
        model.tabs.filter { $0.folderID == folderId }
    }

    func folder(for folderId: UUID?, model: BrowserTabModel) -> TabFolder? {
        guard let folderId else { return nil }
        return model.folders.first { $0.id == folderId }
    }

    func tab(for tabId: UUID, model: BrowserTabModel) -> Tab? {
        model.tabsByID[tabId]
    }

    func validFolderId(_ folderId: UUID?, model: BrowserTabModel) -> UUID? {
        guard let folderId else { return nil }
        return model.folders.contains(where: { $0.id == folderId }) ? folderId : nil
    }

    func orderedTabIDs(from ids: [UUID], model: BrowserTabModel) -> [UUID] {
        let uniqueIDs = Set(ids)
        return model.tabs.map(\.id).filter { uniqueIDs.contains($0) }
    }

    @discardableResult
    func reorderTabs(
        _ tabIDs: [UUID],
        placement: TabInsertionPlacement,
        model: inout BrowserTabModel
    ) -> Bool {
        let orderedTargetIDs = orderedTabIDs(from: tabIDs, model: model)
        guard !orderedTargetIDs.isEmpty else { return false }

        let movingIDSet = Set(orderedTargetIDs)
        let movingTabs = model.tabs.filter { movingIDSet.contains($0.id) }
        var remainingTabs = model.tabs.filter { !movingIDSet.contains($0.id) }

        let insertionIndex: Int
        switch placement {
        case .before(let tabID):
            guard let targetIndex = remainingTabs.firstIndex(where: { $0.id == tabID }) else {
                return false
            }
            insertionIndex = targetIndex
        case .after(let tabID):
            guard let targetIndex = remainingTabs.firstIndex(where: { $0.id == tabID }) else {
                return false
            }
            insertionIndex = targetIndex + 1
        case .end:
            insertionIndex = remainingTabs.count
        }

        let originalIDs = model.tabs.map(\.id)
        remainingTabs.insert(contentsOf: movingTabs, at: insertionIndex)

        let reorderedIDs = remainingTabs.map(\.id)
        guard reorderedIDs != originalIDs else { return false }

        model.tabs = remainingTabs
        model.tabsByID = Dictionary(uniqueKeysWithValues: remainingTabs.map { ($0.id, $0) })
        synchronizeFolders(in: &model)
        return true
    }

    func applyFolderMembership(for tabIDs: [UUID], folderId: UUID?, model: inout BrowserTabModel) {
        for tabID in tabIDs {
            model.tabsByID[tabID]?.folderID = folderId
        }
        synchronizeFolders(in: &model)
    }

    func recordLastActiveTab(_ tabId: UUID, model: inout BrowserTabModel) {
        guard let folderId = model.tabsByID[tabId]?.folderID,
              let index = model.folders.firstIndex(where: { $0.id == folderId }) else {
            return
        }

        if model.folders[index].lastActiveTabID != tabId {
            model.folders[index].lastActiveTabID = tabId
            model.folders[index].touch()
        }
    }

    func synchronizeFolders(in model: inout BrowserTabModel) {
        for index in model.folders.indices {
            let folderId = model.folders[index].id
            let orderedTabIDs = model.tabs.filter { $0.folderID == folderId }.map(\.id)
            let hadChanges = model.folders[index].tabIDs != orderedTabIDs

            model.folders[index].tabIDs = orderedTabIDs

            if let lastActiveTabID = model.folders[index].lastActiveTabID,
               !orderedTabIDs.contains(lastActiveTabID) {
                model.folders[index].lastActiveTabID = orderedTabIDs.first
            }

            if hadChanges {
                model.folders[index].touch()
            }
        }
    }

    func hydrateFolderMembershipFromRestoredState(in model: inout BrowserTabModel) {
        let validFolderIDs = Set(model.folders.map(\.id))
        var fallbackAssignments: [UUID: UUID] = [:]

        for folder in model.folders {
            for tabID in folder.tabIDs where fallbackAssignments[tabID] == nil {
                fallbackAssignments[tabID] = folder.id
            }
        }

        for tab in model.tabs {
            if let folderID = tab.folderID, validFolderIDs.contains(folderID) {
                continue
            }
            tab.folderID = fallbackAssignments[tab.id]
        }

        synchronizeFolders(in: &model)
    }
}

struct TabSelectionController {
    func replacementVisibleTabID(afterRemovingAt index: Int, model: BrowserTabModel) -> UUID? {
        guard !model.tabs.isEmpty else { return nil }

        if index < model.tabs.count {
            return model.tabs[index].id
        }

        let safeUpperBound = min(index, model.tabs.count)
        if safeUpperBound > 0 {
            return model.tabs[safeUpperBound - 1].id
        }

        return nil
    }

    func resolvedTabIDForFolderSelection(
        _ folderId: UUID?,
        preferredTabID: UUID?,
        model: BrowserTabModel,
        activeFolderId: UUID?
    ) -> UUID? {
        let scopedTabs = model.tabs.filter { $0.folderID == folderId }

        if let preferredTabID,
           scopedTabs.contains(where: { $0.id == preferredTabID }) {
            return preferredTabID
        }

        if let folderId,
           let folder = model.folders.first(where: { $0.id == folderId }),
           let lastActiveTabID = folder.lastActiveTabID,
           scopedTabs.contains(where: { $0.id == lastActiveTabID }) {
            return lastActiveTabID
        }

        if folderId == nil,
           let preferredTabID,
           model.tabsByID[preferredTabID]?.folderID == nil {
            return preferredTabID
        }

        if let firstTabID = scopedTabs.first?.id {
            return firstTabID
        }

        return resolvedVisibleTabID(preferredTabID: preferredTabID, model: model, activeFolderId: activeFolderId)
    }

    func resolvedVisibleTabID(
        preferredTabID: UUID?,
        model: BrowserTabModel,
        activeFolderId: UUID?
    ) -> UUID? {
        let scopedTabs = model.tabs
        guard !scopedTabs.isEmpty else { return nil }

        if let preferredTabID,
           scopedTabs.contains(where: { $0.id == preferredTabID }) {
            return preferredTabID
        }

        if let folderId = activeFolderId,
           let folder = model.folders.first(where: { $0.id == folderId }),
           let lastActiveTabID = folder.lastActiveTabID,
           scopedTabs.contains(where: { $0.id == lastActiveTabID }) {
            return lastActiveTabID
        }

        return scopedTabs.first?.id
    }

    func setSingleSelection(
        _ tabId: UUID?,
        visibleTabs: [Tab],
        selection: inout BrowserSelectionModel
    ) {
        if let tabId,
           visibleTabs.contains(where: { $0.id == tabId }) {
            selection.selectedTabIDs = [tabId]
            selection.tabSelectionAnchorId = tabId
        } else {
            selection.selectedTabIDs = []
            selection.tabSelectionAnchorId = nil
        }
    }

    func sanitizeSelection(
        visibleTabs: [Tab],
        selection: inout BrowserSelectionModel
    ) {
        let visibleIDSet = Set(visibleTabs.map(\.id))
        selection.selectedTabIDs = selection.selectedTabIDs.intersection(visibleIDSet)

        if let anchorId = selection.tabSelectionAnchorId,
           !visibleIDSet.contains(anchorId) {
            selection.tabSelectionAnchorId = selection.activeTabId
        }

        if selection.selectedTabIDs.isEmpty {
            setSingleSelection(selection.activeTabId, visibleTabs: visibleTabs, selection: &selection)
        }
    }

    func activateTab(
        _ id: UUID,
        selectionMode: TabSelectionMode,
        followTabFolder: Bool,
        model: BrowserTabModel,
        selection: inout BrowserSelectionModel,
        validFolderIDs: Set<UUID>
    ) {
        guard let tab = model.tabsByID[id] else { return }
        let previousAnchor = selection.tabSelectionAnchorId ?? selection.activeTabId ?? id

        if followTabFolder {
            if let folderID = tab.folderID, validFolderIDs.contains(folderID) {
                selection.activeFolderId = folderID
            } else {
                selection.activeFolderId = nil
            }
        }

        selection.activeTabId = id

        switch selectionMode {
        case .replace:
            setSingleSelection(id, visibleTabs: model.tabs, selection: &selection)
        case .add:
            var newSelection = Set(model.tabs.map(\.id).filter { selection.selectedTabIDs.contains($0) })
            if newSelection.contains(id) {
                newSelection.remove(id)
            } else {
                newSelection.insert(id)
            }

            let visibleIDSet = Set(model.tabs.map(\.id))
            newSelection = newSelection.intersection(visibleIDSet)

            if newSelection.isEmpty {
                newSelection.insert(id)
            }

            selection.selectedTabIDs = newSelection
            selection.tabSelectionAnchorId = id
        case .range:
            let orderedVisibleIDs = model.tabs.map(\.id)
            guard let anchorIndex = orderedVisibleIDs.firstIndex(of: previousAnchor),
                  let selectedIndex = orderedVisibleIDs.firstIndex(of: id) else {
                setSingleSelection(id, visibleTabs: model.tabs, selection: &selection)
                return
            }

            let lowerBound = min(anchorIndex, selectedIndex)
            let upperBound = max(anchorIndex, selectedIndex)
            selection.selectedTabIDs = Set(orderedVisibleIDs[lowerBound...upperBound])
            selection.tabSelectionAnchorId = previousAnchor
        }
    }

    func contextActionTabIDs(
        for contextTabId: UUID,
        model: BrowserTabModel,
        selection: BrowserSelectionModel
    ) -> [UUID] {
        let visibleIDs = Set(model.tabs.map(\.id))
        if selection.selectedTabIDs.contains(contextTabId) {
            let selectedVisible = model.tabs
                .filter { visibleIDs.contains($0.id) && selection.selectedTabIDs.contains($0.id) }
                .map(\.id)
            if !selectedVisible.isEmpty {
                return selectedVisible
            }
        }
        return [contextTabId]
    }
}

struct BrowserLifecycleController {
    let tabCollectionController: TabCollectionController
    let tabSelectionController: TabSelectionController

    init(
        tabCollectionController: TabCollectionController,
        tabSelectionController: TabSelectionController
    ) {
        self.tabCollectionController = tabCollectionController
        self.tabSelectionController = tabSelectionController
    }

    @discardableResult
    func addTab(
        in folderId: UUID?,
        activate: Bool,
        model: inout BrowserTabModel,
        selection: inout BrowserSelectionModel
    ) -> Tab {
        let tab = tabCollectionController.appendTab(
            folderID: tabCollectionController.validFolderId(folderId, model: model),
            model: &model
        )

        if activate {
            activateTab(
                tab.id,
                selectionMode: .replace,
                followTabFolder: true,
                model: &model,
                selection: &selection
            )
        }

        return tab
    }

    @discardableResult
    func addTab(
        withURL url: URL,
        in folderId: UUID?,
        activate: Bool,
        model: inout BrowserTabModel,
        selection: inout BrowserSelectionModel
    ) -> Tab {
        let tab = tabCollectionController.appendTab(
            url: url,
            folderID: tabCollectionController.validFolderId(folderId, model: model),
            loadURLImmediately: true,
            model: &model
        )

        if activate {
            activateTab(
                tab.id,
                selectionMode: .replace,
                followTabFolder: true,
                model: &model,
                selection: &selection
            )
        }

        return tab
    }

    func closeTab(
        _ id: UUID,
        model: inout BrowserTabModel,
        selection: inout BrowserSelectionModel
    ) -> Tab? {
        guard model.tabs.count > 1 else { return nil }
        guard let removal = tabCollectionController.removeTab(id, from: &model) else { return nil }

        let tab = removal.tab
        let wasActive = selection.activeTabId == id

        tabCollectionController.pushClosedTab(tab, into: &model)
        selection.selectedTabIDs.remove(id)
        if selection.tabSelectionAnchorId == id {
            selection.tabSelectionAnchorId = nil
        }

        if wasActive {
            selection.activeTabId = tabSelectionController.replacementVisibleTabID(
                afterRemovingAt: removal.index,
                model: model
            )
            if let activeTabId = selection.activeTabId {
                tabCollectionController.recordLastActiveTab(activeTabId, model: &model)
            }
            tabSelectionController.setSingleSelection(
                selection.activeTabId,
                visibleTabs: model.tabs,
                selection: &selection
            )
        } else {
            tabSelectionController.sanitizeSelection(visibleTabs: model.tabs, selection: &selection)
        }

        return tab
    }

    func activateTab(
        _ id: UUID,
        selectionMode: TabSelectionMode,
        followTabFolder: Bool,
        model: inout BrowserTabModel,
        selection: inout BrowserSelectionModel
    ) {
        tabSelectionController.activateTab(
            id,
            selectionMode: selectionMode,
            followTabFolder: followTabFolder,
            model: model,
            selection: &selection,
            validFolderIDs: Set(model.folders.map(\.id))
        )

        if let activeTabId = selection.activeTabId {
            tabCollectionController.recordLastActiveTab(activeTabId, model: &model)
        }
    }

    @discardableResult
    func reopenLastClosedTab(
        model: inout BrowserTabModel,
        selection: inout BrowserSelectionModel
    ) -> Tab? {
        guard let closedInfo = tabCollectionController.reopenLastClosedTab(in: &model) else { return nil }

        let tab = tabCollectionController.appendTab(
            title: closedInfo.title,
            folderID: tabCollectionController.validFolderId(closedInfo.folderID, model: model),
            isChatTab: closedInfo.isChatTab,
            hasConversationStarted: closedInfo.hasConversationStarted,
            conversationId: closedInfo.conversationId,
            model: &model
        )

        if let url = closedInfo.url {
            tab.load(url.absoluteString)
        }

        activateTab(
            tab.id,
            selectionMode: .replace,
            followTabFolder: true,
            model: &model,
            selection: &selection
        )

        return tab
    }

    func restoreState(
        _ state: WorkspaceTabState,
        model: inout BrowserTabModel,
        selection: inout BrowserSelectionModel
    ) {
        tabCollectionController.restoreTabs(from: state, in: &model)
        selection.activeFolderId = tabCollectionController.validFolderId(state.activeFolderId, model: model)

        if selection.activeFolderId == nil,
           let restoredActiveTab = state.activeTabId.flatMap({ model.tabsByID[$0] }) {
            selection.activeFolderId = tabCollectionController.validFolderId(restoredActiveTab.folderID, model: model)
        }

        selection.activeTabId = tabSelectionController.resolvedVisibleTabID(
            preferredTabID: state.activeTabId,
            model: model,
            activeFolderId: selection.activeFolderId
        )

        if let activeTabId = selection.activeTabId {
            tabCollectionController.recordLastActiveTab(activeTabId, model: &model)
        }

        tabSelectionController.setSingleSelection(
            selection.activeTabId,
            visibleTabs: model.tabs,
            selection: &selection
        )
    }

    func loadEmptyWorkspace(
        model: inout BrowserTabModel,
        selection: inout BrowserSelectionModel
    ) {
        tabCollectionController.clearAllTabs(in: &model)
        model.folders = []
        selection = BrowserSelectionModel()
        _ = addTab(in: nil, activate: true, model: &model, selection: &selection)
    }
}

struct BrowserFolderController {
    let tabCollectionController: TabCollectionController
    let tabSelectionController: TabSelectionController

    init(
        tabCollectionController: TabCollectionController,
        tabSelectionController: TabSelectionController
    ) {
        self.tabCollectionController = tabCollectionController
        self.tabSelectionController = tabSelectionController
    }

    func selectFolder(
        _ folderId: UUID?,
        model: inout BrowserTabModel,
        selection: inout BrowserSelectionModel
    ) {
        selection.activeFolderId = tabCollectionController.validFolderId(folderId, model: model)
        selection.activeTabId = tabSelectionController.resolvedTabIDForFolderSelection(
            selection.activeFolderId,
            preferredTabID: selection.activeTabId,
            model: model,
            activeFolderId: selection.activeFolderId
        )

        if let activeTabId = selection.activeTabId {
            tabCollectionController.recordLastActiveTab(activeTabId, model: &model)
        }

        tabSelectionController.setSingleSelection(
            selection.activeTabId,
            visibleTabs: model.tabs,
            selection: &selection
        )
    }

    @discardableResult
    func createFolder(
        name: String,
        color: String,
        movingTabIDs: [UUID],
        model: inout BrowserTabModel,
        selection: inout BrowserSelectionModel
    ) -> UUID {
        let folderID = tabCollectionController.createFolder(name: name, color: color, in: &model)
        let orderedTargetIDs = tabCollectionController.orderedTabIDs(from: movingTabIDs, model: model)

        if orderedTargetIDs.isEmpty {
            selection.activeFolderId = folderID
            selection.activeTabId = tabSelectionController.resolvedVisibleTabID(
                preferredTabID: selection.activeTabId,
                model: model,
                activeFolderId: selection.activeFolderId
            )
            tabSelectionController.setSingleSelection(
                selection.activeTabId,
                visibleTabs: model.tabs,
                selection: &selection
            )
            return folderID
        }

        tabCollectionController.applyFolderMembership(for: orderedTargetIDs, folderId: folderID, model: &model)
        selection.activeFolderId = folderID
        selection.activeTabId = tabSelectionController.resolvedVisibleTabID(
            preferredTabID: selection.activeTabId ?? orderedTargetIDs.first,
            model: model,
            activeFolderId: selection.activeFolderId
        )

        if let activeTabId = selection.activeTabId {
            tabCollectionController.recordLastActiveTab(activeTabId, model: &model)
        }

        tabSelectionController.setSingleSelection(
            selection.activeTabId,
            visibleTabs: model.tabs,
            selection: &selection
        )

        return folderID
    }

    func updateFolder(id: UUID, name: String, color: String, model: inout BrowserTabModel) {
        tabCollectionController.updateFolder(id: id, name: name, color: color, in: &model)
    }

    @discardableResult
    func deleteFolder(
        _ id: UUID,
        model: inout BrowserTabModel,
        selection: inout BrowserSelectionModel
    ) -> Bool {
        guard model.folders.contains(where: { $0.id == id }) else { return false }

        tabCollectionController.applyFolderMembership(
            for: tabCollectionController.tabs(in: id, model: model).map(\.id),
            folderId: nil,
            model: &model
        )
        tabCollectionController.deleteFolder(id, in: &model)

        if selection.activeFolderId == id {
            selection.activeFolderId = nil
        }

        selection.activeTabId = tabSelectionController.resolvedVisibleTabID(
            preferredTabID: selection.activeTabId,
            model: model,
            activeFolderId: selection.activeFolderId
        )

        if let activeTabId = selection.activeTabId {
            tabCollectionController.recordLastActiveTab(activeTabId, model: &model)
        }

        tabSelectionController.setSingleSelection(
            selection.activeTabId,
            visibleTabs: model.tabs,
            selection: &selection
        )

        return true
    }

    @discardableResult
    func moveTabs(
        _ tabIDs: [UUID],
        toFolder folderId: UUID?,
        placement: TabInsertionPlacement? = nil,
        model: inout BrowserTabModel,
        selection: inout BrowserSelectionModel
    ) -> Bool {
        let orderedTargetIDs = tabCollectionController.orderedTabIDs(from: tabIDs, model: model)
        guard !orderedTargetIDs.isEmpty else { return false }

        if let placement {
            _ = tabCollectionController.reorderTabs(orderedTargetIDs, placement: placement, model: &model)
        }

        let resolvedFolderId = tabCollectionController.validFolderId(folderId, model: model)

        tabCollectionController.applyFolderMembership(
            for: orderedTargetIDs,
            folderId: resolvedFolderId,
            model: &model
        )

        if let activeTabId = selection.activeTabId,
           orderedTargetIDs.contains(activeTabId) {
            selection.activeFolderId = resolvedFolderId
        }

        selection.activeTabId = tabSelectionController.resolvedVisibleTabID(
            preferredTabID: selection.activeTabId,
            model: model,
            activeFolderId: selection.activeFolderId
        )

        if let activeTabId = selection.activeTabId {
            tabCollectionController.recordLastActiveTab(activeTabId, model: &model)
        }

        tabSelectionController.setSingleSelection(
            selection.activeTabId,
            visibleTabs: model.tabs,
            selection: &selection
        )

        return true
    }

    @discardableResult
    func reorderTabs(
        _ tabIDs: [UUID],
        placement: TabInsertionPlacement,
        model: inout BrowserTabModel,
        selection: inout BrowserSelectionModel
    ) -> Bool {
        let didReorder = tabCollectionController.reorderTabs(tabIDs, placement: placement, model: &model)
        guard didReorder else { return false }

        tabSelectionController.sanitizeSelection(visibleTabs: model.tabs, selection: &selection)

        if let activeTabId = selection.activeTabId {
            tabCollectionController.recordLastActiveTab(activeTabId, model: &model)
        }

        return true
    }
}

@MainActor
struct WorkspaceSessionController {
    let workspaceStateStore: WorkspaceStateStore
    var currentWorkspaceId: UUID?

    init(workspaceStateStore: WorkspaceStateStore) {
        self.workspaceStateStore = workspaceStateStore
    }

    mutating func bind(to workspaceId: UUID) -> UUID? {
        let previousWorkspaceID = currentWorkspaceId != workspaceId ? currentWorkspaceId : nil
        currentWorkspaceId = workspaceId
        return previousWorkspaceID
    }

    func saveState(_ state: WorkspaceTabState, for workspaceId: UUID) {
        workspaceStateStore.saveTabState(state, workspaceId)
    }

    func loadState(for workspaceId: UUID) -> WorkspaceTabState? {
        workspaceStateStore.getTabState(workspaceId)
    }

    func clearState(for workspaceId: UUID) {
        workspaceStateStore.clearTabState(workspaceId)
    }
}

final class BrowserStateEffects {
    private let captureScreenshotImpl: @MainActor (Tab) async -> Void
    private let removeScreenshotImpl: @MainActor (UUID) -> Void
    private let saveConversationImpl: @MainActor () -> Void
    private let clearSnapshotImpl: @MainActor (UUID) -> Void

    init() {
        self.captureScreenshotImpl = { tab in
            await TabScreenshotManager.shared.captureScreenshot(for: tab)
        }
        self.removeScreenshotImpl = { tabId in
            TabScreenshotManager.shared.removeScreenshot(for: tabId)
        }
        self.saveConversationImpl = {
            ConversationManager.shared.saveCurrentConversation()
        }
        self.clearSnapshotImpl = { conversationID in
            AgentManager.shared.clearSnapshot(for: conversationID)
        }
    }

    init(
        screenshotManager: TabScreenshotManager,
        conversationManager: ConversationManager,
        agentManager: AgentManager
    ) {
        self.captureScreenshotImpl = { tab in
            await screenshotManager.captureScreenshot(for: tab)
        }
        self.removeScreenshotImpl = { tabId in
            screenshotManager.removeScreenshot(for: tabId)
        }
        self.saveConversationImpl = {
            conversationManager.saveCurrentConversation()
        }
        self.clearSnapshotImpl = { conversationID in
            agentManager.clearSnapshot(for: conversationID)
        }
    }

    func captureScreenshot(of tab: Tab?) {
        guard let tab else { return }
        Task { @MainActor in
            await captureScreenshotImpl(tab)
        }
    }

    func removeScreenshot(for tabId: UUID) {
        Task { @MainActor in
            removeScreenshotImpl(tabId)
        }
    }

    func handleClosing(tab: Tab) {
        if tab.isChatTab {
            let conversationID = tab.conversationId
            Task { @MainActor in
                saveConversationImpl()
                clearSnapshotImpl(conversationID)
            }
        }

        tab.cleanup()
        removeScreenshot(for: tab.id)
    }

    func ensureActiveTabLoadedIfNeeded(_ tab: Tab?) {
        guard let tab,
              let url = tab.url,
              !tab.hasWebView else { return }
        tab.restore(url.absoluteString, eagerly: true)
    }
}
