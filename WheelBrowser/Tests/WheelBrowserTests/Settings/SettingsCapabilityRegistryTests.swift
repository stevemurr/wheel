import Testing
@testable import WheelBrowser

@MainActor
@Suite("SettingsCapabilityRegistry", .serialized)
struct SettingsCapabilityRegistryTests {
    @Test("Validation sorts dependent AI actions into apply order")
    func validationSortsDependentAIActions() throws {
        let registry = SettingsCapabilityRegistry.shared

        let validated = try registry.validate(actions: [
            GeneratedSettingsAction(
                actionType: SettingsAssistantActionType.setString.rawValue,
                settingID: "ai.modelID",
                boolValue: nil,
                stringValue: "gpt-4.1",
                intValue: nil,
                doubleValue: nil,
                enumValue: nil
            ),
            GeneratedSettingsAction(
                actionType: SettingsAssistantActionType.setEnum.rawValue,
                settingID: "ai.provider",
                boolValue: nil,
                stringValue: nil,
                intValue: nil,
                doubleValue: nil,
                enumValue: "openai"
            ),
        ])

        #expect(validated.map(\.settingID) == ["ai.provider", "ai.modelID"])
    }

    @Test("Applying AI provider and model actions preserves explicit model choice")
    func applyAIActionsPreservesExplicitModelChoice() async throws {
        let settings = SettingsSnapshot.capture()
        defer { settings.restore() }

        let registry = SettingsCapabilityRegistry.shared
        let coordinator = MockSettingsRuntimeCoordinator()

        let actions = try registry.validate(actions: [
            GeneratedSettingsAction(
                actionType: SettingsAssistantActionType.setString.rawValue,
                settingID: "ai.modelID",
                boolValue: nil,
                stringValue: "gpt-4.1",
                intValue: nil,
                doubleValue: nil,
                enumValue: nil
            ),
            GeneratedSettingsAction(
                actionType: SettingsAssistantActionType.setEnum.rawValue,
                settingID: "ai.provider",
                boolValue: nil,
                stringValue: nil,
                intValue: nil,
                doubleValue: nil,
                enumValue: "openai"
            ),
        ])

        let report = await registry.applyValidatedActions(actions, coordinator: coordinator)

        #expect(report.failedActions.isEmpty)
        #expect(AppSettings.shared.aiProviderID == WheelModelProviderID.openAI.rawValue)
        #expect(AppSettings.shared.aiModelID == "gpt-4.1")
    }

    @Test("Applying semantic search action triggers runtime coordination")
    func applyingSemanticSearchActionTriggersRuntimeCoordination() async throws {
        let settings = SettingsSnapshot.capture()
        defer { settings.restore() }

        let registry = SettingsCapabilityRegistry.shared
        let coordinator = MockSettingsRuntimeCoordinator()

        let actions = try registry.validate(actions: [
            GeneratedSettingsAction(
                actionType: SettingsAssistantActionType.setBool.rawValue,
                settingID: "semanticSearch.enabled",
                boolValue: false,
                stringValue: nil,
                intValue: nil,
                doubleValue: nil,
                enumValue: nil
            )
        ])

        _ = await registry.applyValidatedActions(actions, coordinator: coordinator)

        #expect(AppSettings.shared.semanticSearchEnabled == false)
        #expect(coordinator.semanticSearchChanges == 1)
    }

    @Test("Validation rejects unsupported settings")
    func validationRejectsUnsupportedSettings() throws {
        let registry = SettingsCapabilityRegistry.shared

        #expect(throws: SettingsCapabilityRegistryError.unsupportedSetting("unknown.setting")) {
            try registry.validate(actions: [
                GeneratedSettingsAction(
                    actionType: SettingsAssistantActionType.setBool.rawValue,
                    settingID: "unknown.setting",
                    boolValue: true,
                    stringValue: nil,
                    intValue: nil,
                    doubleValue: nil,
                    enumValue: nil
                )
            ])
        }
    }
}

@MainActor
private final class MockSettingsRuntimeCoordinator: SettingsRuntimeCoordinating {
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
private struct SettingsSnapshot {
    let appearanceModeRaw: String
    let hiddenTabScale: Double
    let shownTabScale: Double
    let aiProviderID: String
    let aiModelID: String
    let aiBaseURL: String
    let aiContextWindowOverride: Int
    let aiAppleGuardrails: String
    let semanticSearchEnabled: Bool
    let extensionsEnabled: Bool
    let adBlockerEnabled: Bool
    let adBlockEasyListEnabled: Bool
    let adBlockEasyPrivacyEnabled: Bool
    let adBlockFanboyAnnoyancesEnabled: Bool
    let mcpServerEnabled: Bool

    static func capture() -> SettingsSnapshot {
        let settings = AppSettings.shared
        return SettingsSnapshot(
            appearanceModeRaw: settings.appearanceModeRaw,
            hiddenTabScale: settings.hiddenTabScale,
            shownTabScale: settings.shownTabScale,
            aiProviderID: settings.aiProviderID,
            aiModelID: settings.aiModelID,
            aiBaseURL: settings.aiBaseURL,
            aiContextWindowOverride: settings.aiContextWindowOverride,
            aiAppleGuardrails: settings.aiAppleGuardrails,
            semanticSearchEnabled: settings.semanticSearchEnabled,
            extensionsEnabled: settings.extensionsEnabled,
            adBlockerEnabled: settings.adBlockerEnabled,
            adBlockEasyListEnabled: settings.adBlockEasyListEnabled,
            adBlockEasyPrivacyEnabled: settings.adBlockEasyPrivacyEnabled,
            adBlockFanboyAnnoyancesEnabled: settings.adBlockFanboyAnnoyancesEnabled,
            mcpServerEnabled: settings.mcpServerEnabled
        )
    }

    func restore() {
        let settings = AppSettings.shared
        settings.appearanceModeRaw = appearanceModeRaw
        settings.hiddenTabScale = hiddenTabScale
        settings.shownTabScale = shownTabScale
        settings.aiProviderID = aiProviderID
        settings.aiModelID = aiModelID
        settings.aiBaseURL = aiBaseURL
        settings.aiContextWindowOverride = aiContextWindowOverride
        settings.aiAppleGuardrails = aiAppleGuardrails
        settings.semanticSearchEnabled = semanticSearchEnabled
        settings.extensionsEnabled = extensionsEnabled
        settings.adBlockerEnabled = adBlockerEnabled
        settings.adBlockEasyListEnabled = adBlockEasyListEnabled
        settings.adBlockEasyPrivacyEnabled = adBlockEasyPrivacyEnabled
        settings.adBlockFanboyAnnoyancesEnabled = adBlockFanboyAnnoyancesEnabled
        settings.mcpServerEnabled = mcpServerEnabled
    }
}
