import SwiftUI

struct OmniBarPanelDescriptor {
    let moduleID: OmniBarModuleID
    let title: String
    let icon: String
    let iconColor: Color
    let borderColor: Color
    let subtitle: String?
    let menuContent: AnyView?
    let content: AnyView
}

@MainActor
protocol OmniBarModule: AnyObject {
    var id: OmniBarModuleID { get }
    var title: String { get }
    var icon: String { get }
    var placeholder: String { get }
    var color: Color { get }

    func activate(in featureModel: OmniBarFeatureModel, reason: OmniBarModuleActivationReason)
    func deactivate(in featureModel: OmniBarFeatureModel)
    func handleInputChanged(in featureModel: OmniBarFeatureModel, text: String)
    func handleSubmit(in featureModel: OmniBarFeatureModel)
    func handleKeyboardCommand(_ command: KeyboardCommand, in featureModel: OmniBarFeatureModel, text: String) -> Bool?
    func clear(in featureModel: OmniBarFeatureModel)
}

@MainActor
protocol OmniBarPanelProviding: OmniBarModule {
    func panelDescriptor(in featureModel: OmniBarFeatureModel) -> OmniBarPanelDescriptor?
    func showsPanelToggle(in featureModel: OmniBarFeatureModel) -> Bool
}

@MainActor
protocol OmniBarSelectableResultsProviding: OmniBarModule, ListSelectable {}

@MainActor
protocol OmniBarAccessoryProviding: OmniBarModule {
    func accessoryView(in featureModel: OmniBarFeatureModel) -> AnyView?
}

@MainActor
struct OmniBarModuleRegistry {
    let modules: [any OmniBarModule]
    private let modulesByID: [OmniBarModuleID: any OmniBarModule]

    init(modules: [any OmniBarModule]) {
        self.modules = modules
        self.modulesByID = Dictionary(uniqueKeysWithValues: modules.map { ($0.id, $0) })
    }

    var orderedModuleIDs: [OmniBarModuleID] {
        modules.map(\.id).filter(BrowserExperience.showsOmniBarModule)
    }

    func module(for id: OmniBarModuleID) -> (any OmniBarModule)? {
        modulesByID[id]
    }

    func module<M: OmniBarModule>(for id: OmniBarModuleID, as type: M.Type) -> M? {
        modulesByID[id] as? M
    }

    func nextID(after id: OmniBarModuleID) -> OmniBarModuleID {
        guard let currentIndex = orderedModuleIDs.firstIndex(of: id) else {
            return orderedModuleIDs.first ?? .address
        }

        let nextIndex = orderedModuleIDs.index(after: currentIndex)
        return nextIndex < orderedModuleIDs.endIndex ? orderedModuleIDs[nextIndex] : orderedModuleIDs[orderedModuleIDs.startIndex]
    }

    func previousID(before id: OmniBarModuleID) -> OmniBarModuleID {
        guard let currentIndex = orderedModuleIDs.firstIndex(of: id) else {
            return orderedModuleIDs.first ?? .address
        }

        if currentIndex == orderedModuleIDs.startIndex {
            return orderedModuleIDs[orderedModuleIDs.index(before: orderedModuleIDs.endIndex)]
        }
        return orderedModuleIDs[orderedModuleIDs.index(before: currentIndex)]
    }

    static func builtIn() -> Self {
        Self(modules: [
            AddressOmniBarModule(),
            SemanticOmniBarModule(),
            AgentOmniBarModule(),
            ReadingListOmniBarModule(),
        ])
    }
}

private struct OmniBarClearInputButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale))
    }
}

@MainActor
final class AddressOmniBarModule: OmniBarPanelProviding, OmniBarSelectableResultsProviding, OmniBarAccessoryProviding {
    let id: OmniBarModuleID = .address
    let title = "Go to"
    let icon = "magnifyingglass"
    let placeholder = "Search or enter URL"
    let color: Color = .accentColor

    let viewModel = SuggestionsViewModel()

    var selectedIndex: Int {
        get { viewModel.selectedIndex }
        set { viewModel.selectedIndex = newValue }
    }

    var selectableCount: Int {
        viewModel.selectableCount
    }

    func activate(in featureModel: OmniBarFeatureModel, reason: OmniBarModuleActivationReason) {
        if featureModel.inputText.isEmpty {
            viewModel.loadRecentHistory()
        } else {
            viewModel.updateSuggestions(for: featureModel.inputText)
        }

        if !featureModel.isInputFocused && reason == .focusGain {
            return
        }
        featureModel.setVisiblePanel(.history)
    }

    func deactivate(in featureModel: OmniBarFeatureModel) {
        viewModel.hide()
    }

    func handleInputChanged(in featureModel: OmniBarFeatureModel, text: String) {
        if text.isEmpty {
            viewModel.loadRecentHistory()
        } else {
            viewModel.updateSuggestions(for: text)
        }
    }

    func handleSubmit(in featureModel: OmniBarFeatureModel) {
        if let selected = viewModel.selectedSuggestion {
            featureModel.handleSuggestionSelection(selected)
            return
        }

        featureModel.tab.load(featureModel.inputText)
        featureModel.isInputFocused = false
        viewModel.hide()
        featureModel.dismissVisiblePanel()
    }

    func handleKeyboardCommand(_ command: KeyboardCommand, in featureModel: OmniBarFeatureModel, text: String) -> Bool? {
        nil
    }

    func clear(in featureModel: OmniBarFeatureModel) {
        featureModel.inputText = ""
        viewModel.clear()
    }

    func showsPanelToggle(in featureModel: OmniBarFeatureModel) -> Bool {
        false
    }

    func panelDescriptor(in featureModel: OmniBarFeatureModel) -> OmniBarPanelDescriptor? {
        guard featureModel.isPanelVisible(for: id) else { return nil }

        return OmniBarPanelDescriptor(
            moduleID: id,
            title: title,
            icon: icon,
            iconColor: color,
            borderColor: .blue,
            subtitle: featureModel.historyPanelSubtitle,
            menuContent: nil,
            content: AnyView(
                HistoryPanelContent(
                    viewModel: viewModel,
                    searchText: featureModel.inputText,
                    onSelect: { [weak featureModel] suggestion in
                        featureModel?.handleSuggestionSelection(suggestion)
                    }
                )
            )
        )
    }

    func accessoryView(in featureModel: OmniBarFeatureModel) -> AnyView? {
        guard featureModel.isInputFocused, !featureModel.inputText.isEmpty else { return nil }
        return AnyView(OmniBarClearInputButton { [weak featureModel] in
            featureModel?.inputText = ""
            self.viewModel.clear()
        })
    }
}

@MainActor
final class SemanticOmniBarModule: OmniBarPanelProviding, OmniBarSelectableResultsProviding, OmniBarAccessoryProviding {
    let id: OmniBarModuleID = .semantic
    let title = "Semantic Search"
    let icon = "brain.head.profile"
    let placeholder = "Search history semantically..."
    let color: Color = .orange

    let viewModel = SemanticSearchViewModel()

    var selectedIndex: Int {
        get { viewModel.selectedIndex }
        set { viewModel.selectedIndex = newValue }
    }

    var selectableCount: Int {
        viewModel.selectableCount
    }

    func activate(in featureModel: OmniBarFeatureModel, reason: OmniBarModuleActivationReason) {
        if !featureModel.inputText.isEmpty {
            viewModel.search(query: featureModel.inputText)
        }
        featureModel.setVisiblePanel(.semantic)
    }

    func deactivate(in featureModel: OmniBarFeatureModel) {
        viewModel.clear()
    }

    func handleInputChanged(in featureModel: OmniBarFeatureModel, text: String) {
        viewModel.search(query: text)
    }

    func handleSubmit(in featureModel: OmniBarFeatureModel) {
        guard let selected = viewModel.selectedResult else { return }
        featureModel.handleSemanticSelection(selected)
    }

    func handleKeyboardCommand(_ command: KeyboardCommand, in featureModel: OmniBarFeatureModel, text: String) -> Bool? {
        nil
    }

    func clear(in featureModel: OmniBarFeatureModel) {
        featureModel.inputText = ""
        viewModel.clear()
    }

    func showsPanelToggle(in featureModel: OmniBarFeatureModel) -> Bool {
        featureModel.mode == id && !viewModel.results.isEmpty
    }

    func panelDescriptor(in featureModel: OmniBarFeatureModel) -> OmniBarPanelDescriptor? {
        guard featureModel.isPanelVisible(for: id) else { return nil }

        let searchManager = SemanticSearchManagerV2.shared
        let subtitle: String
        if viewModel.isSearching {
            subtitle = "Searching..."
        } else if !viewModel.results.isEmpty {
            subtitle = "\(viewModel.results.count) results"
        } else {
            subtitle = "\(searchManager.stats.pageCount) pages indexed"
        }

        return OmniBarPanelDescriptor(
            moduleID: id,
            title: title,
            icon: icon,
            iconColor: color,
            borderColor: color,
            subtitle: subtitle,
            menuContent: AnyView(
                Button("Clear Index") {
                    Task { await searchManager.clearIndex() }
                }
            ),
            content: AnyView(
                SemanticSearchPanelContent(
                    viewModel: viewModel,
                    searchManager: searchManager,
                    searchText: featureModel.inputText,
                    onSelect: { [weak featureModel] result in
                        featureModel?.handleSemanticSelection(result)
                    }
                )
            )
        )
    }

    func accessoryView(in featureModel: OmniBarFeatureModel) -> AnyView? {
        guard featureModel.isInputFocused, !featureModel.inputText.isEmpty else { return nil }
        return AnyView(OmniBarClearInputButton { [weak featureModel] in
            featureModel?.inputText = ""
            self.viewModel.clear()
        })
    }
}

@MainActor
final class AgentOmniBarModule: OmniBarPanelProviding, OmniBarAccessoryProviding {
    let id: OmniBarModuleID = .agent
    let title = "Agent"
    let icon = "wand.and.stars"
    let placeholder = "Describe a task for the agent..."
    let color: Color = .green

    func activate(in featureModel: OmniBarFeatureModel, reason: OmniBarModuleActivationReason) {
        featureModel.dismissVisiblePanel()
    }

    func deactivate(in featureModel: OmniBarFeatureModel) {}

    func handleInputChanged(in featureModel: OmniBarFeatureModel, text: String) {}

    func handleSubmit(in featureModel: OmniBarFeatureModel) {
        let task = featureModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }

        featureModel.inputText = ""
        featureModel.dismissVisiblePanel()

        Task {
            _ = await featureModel.agentEngine.run(task: task)
        }
    }

    func handleKeyboardCommand(_ command: KeyboardCommand, in featureModel: OmniBarFeatureModel, text: String) -> Bool? {
        nil
    }

    func clear(in featureModel: OmniBarFeatureModel) {
        featureModel.inputText = ""
    }

    func showsPanelToggle(in featureModel: OmniBarFeatureModel) -> Bool {
        featureModel.mode == id && (!featureModel.agentEngine.steps.isEmpty || featureModel.agentEngine.isRunning)
    }

    func panelDescriptor(in featureModel: OmniBarFeatureModel) -> OmniBarPanelDescriptor? {
        guard featureModel.isPanelVisible(for: id) else { return nil }

        let subtitle: String
        if featureModel.agentEngine.isRunning {
            subtitle = featureModel.agentEngine.progress
        } else if !featureModel.agentEngine.steps.isEmpty {
            if let lastStep = featureModel.agentEngine.steps.last, lastStep.type == .done {
                subtitle = "Completed"
            } else if featureModel.agentEngine.error != nil {
                subtitle = "Failed"
            } else {
                subtitle = "\(featureModel.agentEngine.steps.count) steps"
            }
        } else {
            subtitle = "Ready"
        }

        return OmniBarPanelDescriptor(
            moduleID: id,
            title: title,
            icon: icon,
            iconColor: color,
            borderColor: color,
            subtitle: subtitle,
            menuContent: AnyView(
                Group {
                    Button("Cancel Task") { featureModel.agentEngine.cancel() }
                        .disabled(!featureModel.agentEngine.isRunning)
                    Divider()
                    Button("Clear History") { featureModel.agentEngine.clearHistory() }
                        .disabled(featureModel.agentEngine.steps.isEmpty && featureModel.agentEngine.lastResult == nil)
                }
            ),
            content: AnyView(
                AgentPanelContent(
                    agentEngine: featureModel.agentEngine,
                    browserState: featureModel.browserState
                )
            )
        )
    }

    func accessoryView(in featureModel: OmniBarFeatureModel) -> AnyView? {
        AnyView(
            AgentActionButton(
                agentEngine: featureModel.agentEngine,
                inputText: featureModel.inputText,
                onSubmit: { [weak featureModel] in
                    featureModel?.handleSubmit()
                }
            )
        )
    }
}

@MainActor
final class ReadingListOmniBarModule: OmniBarPanelProviding, OmniBarSelectableResultsProviding, OmniBarAccessoryProviding {
    let id: OmniBarModuleID = .readingList
    let title = "Reading List"
    let icon = "bookmark.fill"
    let placeholder = "Search reading list..."
    let color: Color = .pink

    let viewModel = ReadingListViewModel()

    var selectedIndex: Int {
        get { viewModel.selectedIndex }
        set { viewModel.selectedIndex = newValue }
    }

    var selectableCount: Int {
        viewModel.selectableCount
    }

    func activate(in featureModel: OmniBarFeatureModel, reason: OmniBarModuleActivationReason) {
        viewModel.loadSavedPages()
        featureModel.setVisiblePanel(.readingList)
    }

    func deactivate(in featureModel: OmniBarFeatureModel) {
        viewModel.clear()
    }

    func handleInputChanged(in featureModel: OmniBarFeatureModel, text: String) {
        viewModel.search(query: text)
    }

    func handleSubmit(in featureModel: OmniBarFeatureModel) {
        guard let selected = viewModel.selectedItem else { return }
        featureModel.handleReadingListSelection(selected)
    }

    func handleKeyboardCommand(_ command: KeyboardCommand, in featureModel: OmniBarFeatureModel, text: String) -> Bool? {
        nil
    }

    func clear(in featureModel: OmniBarFeatureModel) {
        featureModel.inputText = ""
        viewModel.loadSavedPages()
    }

    func showsPanelToggle(in featureModel: OmniBarFeatureModel) -> Bool {
        featureModel.mode == id && !viewModel.items.isEmpty
    }

    func panelDescriptor(in featureModel: OmniBarFeatureModel) -> OmniBarPanelDescriptor? {
        guard featureModel.isPanelVisible(for: id) else { return nil }

        let subtitle: String?
        if viewModel.isLoading {
            subtitle = "Loading..."
        } else if !viewModel.items.isEmpty {
            subtitle = "\(viewModel.items.count) saved"
        } else {
            subtitle = nil
        }

        return OmniBarPanelDescriptor(
            moduleID: id,
            title: title,
            icon: icon,
            iconColor: color,
            borderColor: color,
            subtitle: subtitle,
            menuContent: nil,
            content: AnyView(
                ReadingListPanelContent(
                    viewModel: viewModel,
                    searchText: featureModel.inputText,
                    onSelect: { [weak featureModel] item in
                        featureModel?.handleReadingListSelection(item)
                    }
                )
            )
        )
    }

    func accessoryView(in featureModel: OmniBarFeatureModel) -> AnyView? {
        guard featureModel.isInputFocused, !featureModel.inputText.isEmpty else { return nil }
        return AnyView(OmniBarClearInputButton { [weak featureModel] in
            featureModel?.inputText = ""
            self.viewModel.loadSavedPages()
        })
    }
}
