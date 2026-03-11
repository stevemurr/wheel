import Testing
@testable import WheelBrowser

@MainActor
@Suite("SettingsAssistantManager", .serialized)
struct SettingsAssistantManagerTests {
    @Test("Pending confirmation blocks new prompts")
    func pendingConfirmationBlocksNewPrompts() async throws {
        let snapshot = SettingsAssistantManagerSettingsSnapshot.capture()
        defer { snapshot.restore() }

        let registry = SettingsCapabilityRegistry.shared
        let coordinator = SettingsAssistantManagerMockRuntimeCoordinator()
        let manager = SettingsAssistantManager(
            orchestrator: .shared,
            registry: registry,
            runtimeCoordinator: coordinator
        )

        manager.pendingPlan = SettingsAssistantPendingPlan(
            warnings: [],
            actions: try registry.validate(actions: [
                GeneratedSettingsAction(
                    actionType: SettingsAssistantActionType.setBool.rawValue,
                    settingID: "semanticSearch.enabled",
                    boolValue: true,
                    stringValue: nil,
                    intValue: nil,
                    doubleValue: nil,
                    enumValue: nil
                )
            ]),
            modelDisplayName: "Apple / default",
            source: .appleSettings
        )

        await manager.submitPrompt("Turn on semantic search")

        #expect(manager.messages.isEmpty)
        #expect(manager.error?.contains("Confirm or cancel") == true)
    }

    @Test("Confirm applies pending plan and clears confirmation state")
    func confirmAppliesPendingPlan() async throws {
        let snapshot = SettingsAssistantManagerSettingsSnapshot.capture()
        defer { snapshot.restore() }

        AppSettings.shared.semanticSearchEnabled = true
        let registry = SettingsCapabilityRegistry.shared
        let coordinator = SettingsAssistantManagerMockRuntimeCoordinator()
        let manager = SettingsAssistantManager(
            orchestrator: .shared,
            registry: registry,
            runtimeCoordinator: coordinator
        )

        manager.pendingPlan = SettingsAssistantPendingPlan(
            warnings: ["This reinitializes the local search backend."],
            actions: try registry.validate(actions: [
                GeneratedSettingsAction(
                    actionType: SettingsAssistantActionType.setBool.rawValue,
                    settingID: "semanticSearch.enabled",
                    boolValue: false,
                    stringValue: nil,
                    intValue: nil,
                    doubleValue: nil,
                    enumValue: nil
                )
            ]),
            modelDisplayName: "Apple / default",
            source: .appleSettings
        )

        await manager.confirmPendingPlan()

        #expect(manager.pendingPlan == nil)
        #expect(AppSettings.shared.semanticSearchEnabled == false)
        #expect(coordinator.semanticSearchChanges == 1)
        #expect(manager.messages.count == 2)
        #expect(manager.messages.last?.content.contains("Applied changes") == true)
    }

    @Test("Cancel clears pending plan without changing settings")
    func cancelClearsPendingPlanWithoutChanges() async throws {
        let snapshot = SettingsAssistantManagerSettingsSnapshot.capture()
        defer { snapshot.restore() }

        AppSettings.shared.extensionsEnabled = true
        let registry = SettingsCapabilityRegistry.shared
        let manager = SettingsAssistantManager(
            orchestrator: .shared,
            registry: registry,
            runtimeCoordinator: SettingsAssistantManagerMockRuntimeCoordinator()
        )

        manager.pendingPlan = SettingsAssistantPendingPlan(
            warnings: [],
            actions: try registry.validate(actions: [
                GeneratedSettingsAction(
                    actionType: SettingsAssistantActionType.setBool.rawValue,
                    settingID: "extensions.enabled",
                    boolValue: false,
                    stringValue: nil,
                    intValue: nil,
                    doubleValue: nil,
                    enumValue: nil
                )
            ]),
            modelDisplayName: "Apple / default",
            source: .appleSettings
        )

        manager.cancelPendingPlan()

        #expect(manager.pendingPlan == nil)
        #expect(AppSettings.shared.extensionsEnabled == true)
        #expect(manager.messages.count == 2)
        #expect(manager.messages.last?.content == "Cancelled. No settings were changed.")
    }
}

@MainActor
private final class SettingsAssistantManagerMockRuntimeCoordinator: SettingsRuntimeCoordinating {
    var appearanceChanges = 0
    var semanticSearchChanges = 0
    var extensionChanges = 0
    var adBlockChanges = 0
    var adBlockRefreshes = 0
    var mcpEnabledValues: [Bool] = []

    func handleAppearanceSettingChanged() async {
        appearanceChanges += 1
    }

    func handleSemanticSearchSettingChanged() async {
        semanticSearchChanges += 1
    }

    func handleExtensionsSettingChanged() async {
        extensionChanges += 1
    }

    func handleAdBlockingSettingChanged() async {
        adBlockChanges += 1
    }

    func refreshAdBlockingLists() async {
        adBlockRefreshes += 1
    }

    func setMCPEnabled(_ enabled: Bool) async {
        mcpEnabledValues.append(enabled)
        AppSettings.shared.mcpServerEnabled = enabled
    }
}

@MainActor
private struct SettingsAssistantManagerSettingsSnapshot {
    let semanticSearchEnabled: Bool
    let extensionsEnabled: Bool

    static func capture() -> SettingsAssistantManagerSettingsSnapshot {
        SettingsAssistantManagerSettingsSnapshot(
            semanticSearchEnabled: AppSettings.shared.semanticSearchEnabled,
            extensionsEnabled: AppSettings.shared.extensionsEnabled
        )
    }

    func restore() {
        AppSettings.shared.semanticSearchEnabled = semanticSearchEnabled
        AppSettings.shared.extensionsEnabled = extensionsEnabled
    }
}
