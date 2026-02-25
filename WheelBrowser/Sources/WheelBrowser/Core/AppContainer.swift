import Foundation

/// Central dependency container for the Wheel Browser application.
///
/// AppContainer provides dependency injection by managing shared instances
/// and factory methods for creating view models and services. This enables
/// better testability and decouples components from concrete implementations.
///
/// Usage:
/// ```swift
/// // Access shared services
/// let browserState = AppContainer.shared.browserState
///
/// // Create view models with dependencies injected
/// let viewModel = AppContainer.shared.makeSuggestionsViewModel()
/// ```
@MainActor
final class AppContainer {
    /// Shared singleton instance
    static let shared = AppContainer()

    // MARK: - Core Services

    /// The browser state managing tabs and navigation
    private(set) lazy var browserState = BrowserState()

    /// Application settings
    private(set) lazy var settings = AppSettings.shared

    /// Workspace manager for workspace switching
    private(set) lazy var workspaceManager = WorkspaceManager.shared

    /// Agent studio manager for AI agents
    private(set) lazy var agentStudioManager = AgentStudioManager.shared

    /// New tab page manager
    private(set) lazy var newTabPageManager = NewTabPageManager.shared

    // MARK: - View Model Factories

    /// Creates a new SuggestionsViewModel with dependencies injected
    func makeSuggestionsViewModel() -> SuggestionsViewModel {
        let viewModel = SuggestionsViewModel()
        viewModel.browserState = browserState
        return viewModel
    }

    /// Creates a new SemanticSearchViewModel with dependencies injected
    func makeSemanticSearchViewModel() -> SemanticSearchViewModel {
        return SemanticSearchViewModel()
    }

    /// Creates a new ReadingListViewModel with dependencies injected
    func makeReadingListViewModel() -> ReadingListViewModel {
        return ReadingListViewModel()
    }

    /// Creates a new MentionSuggestionsViewModel with dependencies injected
    func makeMentionSuggestionsViewModel() -> MentionSuggestionsViewModel {
        return MentionSuggestionsViewModel()
    }

    // MARK: - Initialization

    private init() {
        // Set up initial bindings when container is created
        setupBindings()
    }

    private func setupBindings() {
        // Bind browser state to workspace manager's current workspace if any
        if let currentWorkspaceId = workspaceManager.currentWorkspaceID {
            browserState.bindToWorkspace(currentWorkspaceId)
        }
    }
}
