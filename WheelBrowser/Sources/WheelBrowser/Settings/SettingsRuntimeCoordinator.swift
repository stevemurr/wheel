import Foundation

@MainActor
protocol SemanticSearchRuntimeControlling: AnyObject {
    func reinitialize() async
}

extension SemanticSearchManagerV2: SemanticSearchRuntimeControlling {}

@MainActor
protocol ExtensionRuntimeReloading: AnyObject {
    func reload(preferCachedResourcesOnly: Bool) async
}

extension ExtensionRegistry: ExtensionRuntimeReloading {}

@MainActor
protocol AdBlockRuntimeRefreshing: AnyObject {
    func refresh(force: Bool) async
}

extension ContentBlockerManager: AdBlockRuntimeRefreshing {}

@MainActor
protocol MCPServerControlling: AnyObject {
    var isRunning: Bool { get }
    func start()
    func stop()
}

extension MCPServer: MCPServerControlling {}

@MainActor
protocol SettingsRuntimeCoordinating: AnyObject {
    func handleAppearanceSettingChanged() async
    func handleSemanticSearchSettingChanged() async
    func handleExtensionsSettingChanged() async
    func handleAdBlockingSettingChanged() async
    func refreshAdBlockingLists() async
    func setMCPEnabled(_ enabled: Bool) async
}

@MainActor
final class SettingsRuntimeCoordinator: SettingsRuntimeCoordinating {
    static let shared = SettingsRuntimeCoordinator(
        settings: .shared,
        semanticSearch: SemanticSearchManagerV2.shared,
        extensionRegistry: ExtensionRegistry.shared,
        adBlockManager: ContentBlockerManager.shared,
        mcpServer: MCPServer.shared
    )

    private let settings: AppSettings
    private let semanticSearch: any SemanticSearchRuntimeControlling
    private let extensionRegistry: any ExtensionRuntimeReloading
    private let adBlockManager: any AdBlockRuntimeRefreshing
    private let mcpServer: any MCPServerControlling

    init(
        settings: AppSettings,
        semanticSearch: any SemanticSearchRuntimeControlling,
        extensionRegistry: any ExtensionRuntimeReloading,
        adBlockManager: any AdBlockRuntimeRefreshing,
        mcpServer: any MCPServerControlling
    ) {
        self.settings = settings
        self.semanticSearch = semanticSearch
        self.extensionRegistry = extensionRegistry
        self.adBlockManager = adBlockManager
        self.mcpServer = mcpServer
    }

    func handleAppearanceSettingChanged() async {
        settings.applyAppearance()
    }

    func handleSemanticSearchSettingChanged() async {
        await semanticSearch.reinitialize()
    }

    func handleExtensionsSettingChanged() async {
        await extensionRegistry.reload(preferCachedResourcesOnly: false)
    }

    func handleAdBlockingSettingChanged() async {
        await extensionRegistry.reload(preferCachedResourcesOnly: false)
    }

    func refreshAdBlockingLists() async {
        await adBlockManager.refresh(force: true)
        await extensionRegistry.reload(preferCachedResourcesOnly: false)
    }

    func setMCPEnabled(_ enabled: Bool) async {
        settings.mcpServerEnabled = enabled
        if enabled {
            mcpServer.start()
        } else {
            mcpServer.stop()
        }
    }
}
