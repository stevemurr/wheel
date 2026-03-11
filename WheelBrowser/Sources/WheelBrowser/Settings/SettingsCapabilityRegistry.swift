import Foundation

enum SettingsMutationValue: Equatable, Sendable {
    case bool(Bool)
    case string(String)
    case int(Int)
    case double(Double)
    case enumeration(String)

    var displayText: String {
        switch self {
        case .bool(let value):
            return value ? "Enabled" : "Disabled"
        case .string(let value):
            return value.isEmpty ? "Default / cleared" : value
        case .int(let value):
            return String(value)
        case .double(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(format: "%.2f", value)
        case .enumeration(let value):
            return value
        }
    }
}

struct ValidatedSettingsAction: Equatable, Sendable {
    let settingID: String
    let displayName: String
    let value: SettingsMutationValue
    let applyOrder: Int
    let preview: String
}

struct SettingsActionFailure: Equatable, Sendable {
    let action: ValidatedSettingsAction
    let message: String
}

struct SettingsApplyReport: Equatable, Sendable {
    let appliedActions: [ValidatedSettingsAction]
    let failedActions: [SettingsActionFailure]
}

enum SettingsCapabilityRegistryError: LocalizedError, Equatable {
    case unsupportedSetting(String)
    case duplicateSetting(String)
    case invalidActionType(settingID: String, expected: String)
    case missingValue(settingID: String, expected: String)
    case invalidValue(settingID: String, message: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSetting(let settingID):
            return "Unsupported setting '\(settingID)'."
        case .duplicateSetting(let settingID):
            return "The plan attempted to change '\(settingID)' more than once."
        case .invalidActionType(let settingID, let expected):
            return "Setting '\(settingID)' expects \(expected)."
        case .missingValue(let settingID, let expected):
            return "Setting '\(settingID)' is missing its \(expected) value."
        case .invalidValue(let settingID, let message):
            return "Setting '\(settingID)' is invalid: \(message)"
        }
    }
}

@MainActor
final class SettingsCapabilityRegistry {
    static let shared = SettingsCapabilityRegistry()

    struct Descriptor: Equatable, Sendable {
        let id: String
        let displayName: String
        let aliases: [String]
        let valueTypeDescription: String
        let allowedValuesDescription: String?
        let currentValueDescription: String
    }

    private enum ValueKind {
        case bool
        case string(allowEmpty: Bool)
        case int(range: ClosedRange<Int>)
        case double(range: ClosedRange<Double>)
        case enumeration(map: [String: String], allowedValues: [String])
    }

    private struct Capability {
        let id: String
        let displayName: String
        let aliases: [String]
        let valueKind: ValueKind
        let applyOrder: Int
        let currentValueDescription: @MainActor () -> String
        let previewDescription: (SettingsMutationValue) -> String
        let applyValue: @MainActor (SettingsMutationValue, any SettingsRuntimeCoordinating) async throws -> Void
    }

    private let settings: AppSettings
    private lazy var capabilitiesByID: [String: Capability] = {
        Dictionary(uniqueKeysWithValues: capabilities().map { ($0.id, $0) })
    }()

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    func supportedSettingIDs() -> [String] {
        capabilities().map(\.id)
    }

    func descriptors() -> [Descriptor] {
        capabilities().map { capability in
            Descriptor(
                id: capability.id,
                displayName: capability.displayName,
                aliases: capability.aliases,
                valueTypeDescription: valueTypeDescription(for: capability.valueKind),
                allowedValuesDescription: allowedValuesDescription(for: capability.valueKind),
                currentValueDescription: capability.currentValueDescription()
            )
        }
    }

    func supportedSettingsPrompt() -> String {
        descriptors()
            .map { descriptor in
                var parts = [
                    "\(descriptor.id): \(descriptor.displayName)",
                    "type=\(descriptor.valueTypeDescription)",
                    "aliases=[\(descriptor.aliases.joined(separator: ", "))]",
                    "current=\(descriptor.currentValueDescription)"
                ]
                if let allowedValuesDescription = descriptor.allowedValuesDescription {
                    parts.append("allowed=[\(allowedValuesDescription)]")
                }
                return "- " + parts.joined(separator: "; ")
            }
            .joined(separator: "\n")
    }

    func currentSettingsPrompt() -> String {
        descriptors()
            .map { "- \($0.displayName) (\($0.id)): \($0.currentValueDescription)" }
            .joined(separator: "\n")
    }

    func validate(actions: [GeneratedSettingsAction]) throws -> [ValidatedSettingsAction] {
        var seen = Set<String>()
        var validated: [ValidatedSettingsAction] = []

        for action in actions {
            let settingID = action.settingID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard seen.insert(settingID).inserted else {
                throw SettingsCapabilityRegistryError.duplicateSetting(settingID)
            }

            guard let capability = capabilitiesByID[settingID] else {
                throw SettingsCapabilityRegistryError.unsupportedSetting(settingID)
            }

            let value = try validateValue(for: action, capability: capability)
            validated.append(
                ValidatedSettingsAction(
                    settingID: capability.id,
                    displayName: capability.displayName,
                    value: value,
                    applyOrder: capability.applyOrder,
                    preview: capability.previewDescription(value)
                )
            )
        }

        return validated.sorted {
            if $0.applyOrder != $1.applyOrder {
                return $0.applyOrder < $1.applyOrder
            }
            return $0.settingID < $1.settingID
        }
    }

    func applyValidatedActions(
        _ actions: [ValidatedSettingsAction],
        coordinator: any SettingsRuntimeCoordinating
    ) async -> SettingsApplyReport {
        var appliedActions: [ValidatedSettingsAction] = []
        var failedActions: [SettingsActionFailure] = []

        for action in actions {
            guard let capability = capabilitiesByID[action.settingID] else {
                failedActions.append(
                    SettingsActionFailure(
                        action: action,
                        message: SettingsCapabilityRegistryError.unsupportedSetting(action.settingID).localizedDescription
                    )
                )
                continue
            }

            do {
                try await capability.applyValue(action.value, coordinator)
                appliedActions.append(action)
            } catch {
                failedActions.append(
                    SettingsActionFailure(
                        action: action,
                        message: error.localizedDescription
                    )
                )
            }
        }

        return SettingsApplyReport(
            appliedActions: appliedActions,
            failedActions: failedActions
        )
    }

    private func validateValue(
        for action: GeneratedSettingsAction,
        capability: Capability
    ) throws -> SettingsMutationValue {
        switch capability.valueKind {
        case .bool:
            guard action.normalizedActionType == .setBool else {
                throw SettingsCapabilityRegistryError.invalidActionType(
                    settingID: capability.id,
                    expected: SettingsAssistantActionType.setBool.rawValue
                )
            }
            guard let value = action.boolValue else {
                throw SettingsCapabilityRegistryError.missingValue(
                    settingID: capability.id,
                    expected: "boolValue"
                )
            }
            return .bool(value)

        case .string(let allowEmpty):
            guard action.normalizedActionType == .setString else {
                throw SettingsCapabilityRegistryError.invalidActionType(
                    settingID: capability.id,
                    expected: SettingsAssistantActionType.setString.rawValue
                )
            }
            guard let value = action.stringValue else {
                throw SettingsCapabilityRegistryError.missingValue(
                    settingID: capability.id,
                    expected: "stringValue"
                )
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty && !allowEmpty {
                throw SettingsCapabilityRegistryError.invalidValue(
                    settingID: capability.id,
                    message: "empty string is not allowed"
                )
            }
            return .string(trimmed)

        case .int(let range):
            guard action.normalizedActionType == .setInt else {
                throw SettingsCapabilityRegistryError.invalidActionType(
                    settingID: capability.id,
                    expected: SettingsAssistantActionType.setInt.rawValue
                )
            }
            guard let value = action.intValue else {
                throw SettingsCapabilityRegistryError.missingValue(
                    settingID: capability.id,
                    expected: "intValue"
                )
            }
            guard range.contains(value) else {
                throw SettingsCapabilityRegistryError.invalidValue(
                    settingID: capability.id,
                    message: "expected a value in \(range.lowerBound)...\(range.upperBound)"
                )
            }
            return .int(value)

        case .double(let range):
            guard action.normalizedActionType == .setDouble else {
                throw SettingsCapabilityRegistryError.invalidActionType(
                    settingID: capability.id,
                    expected: SettingsAssistantActionType.setDouble.rawValue
                )
            }
            guard let rawValue = action.doubleValue else {
                throw SettingsCapabilityRegistryError.missingValue(
                    settingID: capability.id,
                    expected: "doubleValue"
                )
            }
            let normalized = normalizeScaleIfNeeded(rawValue, for: capability.id)
            guard range.contains(normalized) else {
                throw SettingsCapabilityRegistryError.invalidValue(
                    settingID: capability.id,
                    message: "expected a value in \(range.lowerBound)...\(range.upperBound)"
                )
            }
            return .double(normalized)

        case .enumeration(let map, let allowedValues):
            guard action.normalizedActionType == .setEnum else {
                throw SettingsCapabilityRegistryError.invalidActionType(
                    settingID: capability.id,
                    expected: SettingsAssistantActionType.setEnum.rawValue
                )
            }
            guard let rawValue = action.enumValue else {
                throw SettingsCapabilityRegistryError.missingValue(
                    settingID: capability.id,
                    expected: "enumValue"
                )
            }
            let normalized = normalizedLookupValue(rawValue)
            guard let canonical = map[normalized] else {
                throw SettingsCapabilityRegistryError.invalidValue(
                    settingID: capability.id,
                    message: "expected one of \(allowedValues.joined(separator: ", "))"
                )
            }
            return .enumeration(canonical)
        }
    }

    private func capabilities() -> [Capability] {
        [
            Capability(
                id: "appearance.mode",
                displayName: "Appearance",
                aliases: ["appearance", "theme", "mode"],
                valueKind: .enumeration(
                    map: enumerationMap(
                        canonicalValues: AppearanceMode.allCases.map(\.rawValue),
                        aliases: [
                            "follow system": AppearanceMode.system.rawValue
                        ]
                    ),
                    allowedValues: AppearanceMode.allCases.map(\.rawValue)
                ),
                applyOrder: 10,
                currentValueDescription: { self.settings.appearanceMode.displayName },
                previewDescription: { value in
                    "Set Appearance to \(self.appearanceDisplayName(for: value))"
                },
                applyValue: { value, coordinator in
                    guard case .enumeration(let rawValue) = value,
                          let mode = AppearanceMode(rawValue: rawValue) else {
                        throw SettingsCapabilityRegistryError.invalidValue(
                            settingID: "appearance.mode",
                            message: "unsupported appearance mode"
                        )
                    }
                    self.settings.appearanceMode = mode
                    await coordinator.handleAppearanceSettingChanged()
                }
            ),
            Capability(
                id: "tabDock.hiddenScale",
                displayName: "Hidden Tab Size",
                aliases: ["hidden tab size", "hidden tab scale", "collapsed tab size"],
                valueKind: .double(range: AppSettings.hiddenTabScaleRange),
                applyOrder: 20,
                currentValueDescription: { self.percentString(self.settings.hiddenTabScale) },
                previewDescription: { value in
                    "Set Hidden Tab Size to \(self.scaleDisplayText(value))"
                },
                applyValue: { value, _ in
                    guard case .double(let rawValue) = value else {
                        throw SettingsCapabilityRegistryError.invalidValue(
                            settingID: "tabDock.hiddenScale",
                            message: "expected a number"
                        )
                    }
                    self.settings.hiddenTabScale = rawValue
                }
            ),
            Capability(
                id: "tabDock.shownScale",
                displayName: "Shown Tab Size",
                aliases: ["shown tab size", "shown tab scale", "expanded tab size"],
                valueKind: .double(range: AppSettings.shownTabScaleRange),
                applyOrder: 21,
                currentValueDescription: { self.percentString(self.settings.shownTabScale) },
                previewDescription: { value in
                    "Set Shown Tab Size to \(self.scaleDisplayText(value))"
                },
                applyValue: { value, _ in
                    guard case .double(let rawValue) = value else {
                        throw SettingsCapabilityRegistryError.invalidValue(
                            settingID: "tabDock.shownScale",
                            message: "expected a number"
                        )
                    }
                    self.settings.shownTabScale = rawValue
                }
            ),
            Capability(
                id: "ai.provider",
                displayName: "AI Provider",
                aliases: ["ai provider", "model provider", "provider"],
                valueKind: .enumeration(
                    map: enumerationMap(
                        canonicalValues: WheelModelProviderID.allCases.map(\.rawValue),
                        aliases: ["openai api": WheelModelProviderID.openAI.rawValue]
                    ),
                    allowedValues: WheelModelProviderID.allCases.map(\.rawValue)
                ),
                applyOrder: 30,
                currentValueDescription: {
                    (WheelModelProviderID(rawValue: self.settings.aiProviderID) ?? .apple).displayName
                },
                previewDescription: { value in
                    "Set AI Provider to \(self.providerDisplayName(for: value))"
                },
                applyValue: { value, _ in
                    guard case .enumeration(let rawValue) = value,
                          let provider = WheelModelProviderID(rawValue: rawValue) else {
                        throw SettingsCapabilityRegistryError.invalidValue(
                            settingID: "ai.provider",
                            message: "unsupported provider"
                        )
                    }
                    self.settings.aiProviderID = provider.rawValue
                    self.settings.aiModelID = provider.defaultModelID
                }
            ),
            Capability(
                id: "ai.modelID",
                displayName: "AI Model ID",
                aliases: ["model", "model id", "model identifier"],
                valueKind: .string(allowEmpty: true),
                applyOrder: 31,
                currentValueDescription: {
                    let provider = WheelModelProviderID(rawValue: self.settings.aiProviderID) ?? .apple
                    let trimmed = self.settings.aiModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? provider.defaultModelID : trimmed
                },
                previewDescription: { value in
                    "Set AI Model ID to \(value.displayText)"
                },
                applyValue: { value, _ in
                    guard case .string(let rawValue) = value else {
                        throw SettingsCapabilityRegistryError.invalidValue(
                            settingID: "ai.modelID",
                            message: "expected a string"
                        )
                    }
                    let provider = WheelModelProviderID(rawValue: self.settings.aiProviderID) ?? .apple
                    self.settings.aiModelID = rawValue.isEmpty ? provider.defaultModelID : rawValue
                }
            ),
            Capability(
                id: "ai.baseURL",
                displayName: "AI Base URL",
                aliases: ["base url", "endpoint", "api base url"],
                valueKind: .string(allowEmpty: true),
                applyOrder: 32,
                currentValueDescription: {
                    let trimmed = self.settings.aiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? "Not set" : trimmed
                },
                previewDescription: { value in
                    switch value {
                    case .string(let rawValue):
                        return rawValue.isEmpty ? "Clear AI Base URL" : "Set AI Base URL to \(rawValue)"
                    default:
                        return "Update AI Base URL"
                    }
                },
                applyValue: { value, _ in
                    guard case .string(let rawValue) = value else {
                        throw SettingsCapabilityRegistryError.invalidValue(
                            settingID: "ai.baseURL",
                            message: "expected a string"
                        )
                    }
                    self.settings.aiBaseURL = rawValue
                }
            ),
            Capability(
                id: "ai.contextWindowOverride",
                displayName: "AI Context Window Override",
                aliases: ["context window", "context window override", "token window"],
                valueKind: .int(range: 0...2_000_000),
                applyOrder: 33,
                currentValueDescription: {
                    self.settings.aiContextWindowOverride > 0
                        ? String(self.settings.aiContextWindowOverride)
                        : "Default"
                },
                previewDescription: { value in
                    switch value {
                    case .int(let rawValue):
                        return rawValue == 0
                            ? "Reset AI Context Window Override to Default"
                            : "Set AI Context Window Override to \(rawValue)"
                    default:
                        return "Update AI Context Window Override"
                    }
                },
                applyValue: { value, _ in
                    guard case .int(let rawValue) = value else {
                        throw SettingsCapabilityRegistryError.invalidValue(
                            settingID: "ai.contextWindowOverride",
                            message: "expected an integer"
                        )
                    }
                    self.settings.aiContextWindowOverride = rawValue
                }
            ),
            Capability(
                id: "ai.appleGuardrails",
                displayName: "Apple Guardrails",
                aliases: ["guardrails", "apple guardrails", "content guardrails"],
                valueKind: .enumeration(
                    map: enumerationMap(
                        canonicalValues: WheelAppleGuardrailsOption.allCases.map(\.rawValue),
                        aliases: [
                            "permissive content transformations": WheelAppleGuardrailsOption.permissiveContentTransformations.rawValue
                        ]
                    ),
                    allowedValues: WheelAppleGuardrailsOption.allCases.map(\.rawValue)
                ),
                applyOrder: 34,
                currentValueDescription: {
                    (WheelAppleGuardrailsOption(rawValue: self.settings.aiAppleGuardrails) ?? .default).displayName
                },
                previewDescription: { value in
                    "Set Apple Guardrails to \(self.guardrailsDisplayName(for: value))"
                },
                applyValue: { value, _ in
                    guard case .enumeration(let rawValue) = value,
                          let guardrails = WheelAppleGuardrailsOption(rawValue: rawValue) else {
                        throw SettingsCapabilityRegistryError.invalidValue(
                            settingID: "ai.appleGuardrails",
                            message: "unsupported guardrails option"
                        )
                    }
                    self.settings.aiAppleGuardrails = guardrails.rawValue
                }
            ),
            Capability(
                id: "semanticSearch.enabled",
                displayName: "Semantic Search",
                aliases: ["semantic search", "semantic indexing"],
                valueKind: .bool,
                applyOrder: 40,
                currentValueDescription: { self.enabledText(self.settings.semanticSearchEnabled) },
                previewDescription: { value in
                    "Turn Semantic Search \(self.onOffText(for: value))"
                },
                applyValue: { value, coordinator in
                    guard case .bool(let enabled) = value else {
                        throw SettingsCapabilityRegistryError.invalidValue(
                            settingID: "semanticSearch.enabled",
                            message: "expected a boolean"
                        )
                    }
                    self.settings.semanticSearchEnabled = enabled
                    await coordinator.handleSemanticSearchSettingChanged()
                }
            ),
            Capability(
                id: "extensions.enabled",
                displayName: "Extensions",
                aliases: ["extensions", "browser extensions"],
                valueKind: .bool,
                applyOrder: 50,
                currentValueDescription: { self.enabledText(self.settings.extensionsEnabled) },
                previewDescription: { value in
                    "Turn Extensions \(self.onOffText(for: value))"
                },
                applyValue: { value, coordinator in
                    guard case .bool(let enabled) = value else {
                        throw SettingsCapabilityRegistryError.invalidValue(
                            settingID: "extensions.enabled",
                            message: "expected a boolean"
                        )
                    }
                    self.settings.extensionsEnabled = enabled
                    await coordinator.handleExtensionsSettingChanged()
                }
            ),
            Capability(
                id: "adBlock.enabled",
                displayName: "Ad Blocker",
                aliases: ["ad blocker", "ad blocking", "adblock"],
                valueKind: .bool,
                applyOrder: 60,
                currentValueDescription: { self.enabledText(self.settings.adBlockerEnabled) },
                previewDescription: { value in
                    "Turn Ad Blocker \(self.onOffText(for: value))"
                },
                applyValue: { value, coordinator in
                    guard case .bool(let enabled) = value else {
                        throw SettingsCapabilityRegistryError.invalidValue(
                            settingID: "adBlock.enabled",
                            message: "expected a boolean"
                        )
                    }
                    self.settings.adBlockerEnabled = enabled
                    await coordinator.handleAdBlockingSettingChanged()
                }
            ),
            Capability(
                id: "adBlock.easyListEnabled",
                displayName: "EasyList",
                aliases: ["easylist", "easy list"],
                valueKind: .bool,
                applyOrder: 61,
                currentValueDescription: { self.enabledText(self.settings.adBlockEasyListEnabled) },
                previewDescription: { value in
                    "Turn EasyList \(self.onOffText(for: value))"
                },
                applyValue: { value, coordinator in
                    guard case .bool(let enabled) = value else {
                        throw SettingsCapabilityRegistryError.invalidValue(
                            settingID: "adBlock.easyListEnabled",
                            message: "expected a boolean"
                        )
                    }
                    self.settings.adBlockEasyListEnabled = enabled
                    await coordinator.handleAdBlockingSettingChanged()
                }
            ),
            Capability(
                id: "adBlock.easyPrivacyEnabled",
                displayName: "EasyPrivacy",
                aliases: ["easyprivacy", "easy privacy"],
                valueKind: .bool,
                applyOrder: 62,
                currentValueDescription: { self.enabledText(self.settings.adBlockEasyPrivacyEnabled) },
                previewDescription: { value in
                    "Turn EasyPrivacy \(self.onOffText(for: value))"
                },
                applyValue: { value, coordinator in
                    guard case .bool(let enabled) = value else {
                        throw SettingsCapabilityRegistryError.invalidValue(
                            settingID: "adBlock.easyPrivacyEnabled",
                            message: "expected a boolean"
                        )
                    }
                    self.settings.adBlockEasyPrivacyEnabled = enabled
                    await coordinator.handleAdBlockingSettingChanged()
                }
            ),
            Capability(
                id: "adBlock.fanboyAnnoyancesEnabled",
                displayName: "Fanboy Annoyances",
                aliases: ["fanboy annoyances", "fanboy"],
                valueKind: .bool,
                applyOrder: 63,
                currentValueDescription: { self.enabledText(self.settings.adBlockFanboyAnnoyancesEnabled) },
                previewDescription: { value in
                    "Turn Fanboy Annoyances \(self.onOffText(for: value))"
                },
                applyValue: { value, coordinator in
                    guard case .bool(let enabled) = value else {
                        throw SettingsCapabilityRegistryError.invalidValue(
                            settingID: "adBlock.fanboyAnnoyancesEnabled",
                            message: "expected a boolean"
                        )
                    }
                    self.settings.adBlockFanboyAnnoyancesEnabled = enabled
                    await coordinator.handleAdBlockingSettingChanged()
                }
            ),
            Capability(
                id: "mcp.enabled",
                displayName: "MCP Server",
                aliases: ["mcp", "mcp server", "model context protocol server"],
                valueKind: .bool,
                applyOrder: 70,
                currentValueDescription: { self.enabledText(self.settings.mcpServerEnabled) },
                previewDescription: { value in
                    "Turn MCP Server \(self.onOffText(for: value))"
                },
                applyValue: { value, coordinator in
                    guard case .bool(let enabled) = value else {
                        throw SettingsCapabilityRegistryError.invalidValue(
                            settingID: "mcp.enabled",
                            message: "expected a boolean"
                        )
                    }
                    await coordinator.setMCPEnabled(enabled)
                }
            ),
        ]
    }

    private func valueTypeDescription(for valueKind: ValueKind) -> String {
        switch valueKind {
        case .bool:
            return "bool"
        case .string:
            return "string"
        case .int:
            return "int"
        case .double:
            return "double"
        case .enumeration:
            return "enum"
        }
    }

    private func allowedValuesDescription(for valueKind: ValueKind) -> String? {
        switch valueKind {
        case .enumeration(_, let allowedValues):
            return allowedValues.joined(separator: ", ")
        case .int(let range):
            return "\(range.lowerBound)...\(range.upperBound)"
        case .double(let range):
            return String(format: "%.2f...%.2f", range.lowerBound, range.upperBound)
        case .bool, .string:
            return nil
        }
    }

    private func enumerationMap(
        canonicalValues: [String],
        aliases: [String: String] = [:]
    ) -> [String: String] {
        var result: [String: String] = [:]
        for value in canonicalValues {
            result[normalizedLookupValue(value)] = value
        }
        for (alias, canonical) in aliases {
            result[normalizedLookupValue(alias)] = canonical
        }
        return result
    }

    private func normalizedLookupValue(_ value: String) -> String {
        value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
    }

    private func enabledText(_ value: Bool) -> String {
        value ? "Enabled" : "Disabled"
    }

    private func onOffText(for value: SettingsMutationValue) -> String {
        switch value {
        case .bool(let enabled):
            return enabled ? "On" : "Off"
        default:
            return value.displayText
        }
    }

    private func percentString(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func scaleDisplayText(_ value: SettingsMutationValue) -> String {
        switch value {
        case .double(let rawValue):
            return percentString(rawValue)
        default:
            return value.displayText
        }
    }

    private func providerDisplayName(for value: SettingsMutationValue) -> String {
        guard case .enumeration(let rawValue) = value,
              let provider = WheelModelProviderID(rawValue: rawValue) else {
            return value.displayText
        }
        return provider.displayName
    }

    private func appearanceDisplayName(for value: SettingsMutationValue) -> String {
        guard case .enumeration(let rawValue) = value,
              let mode = AppearanceMode(rawValue: rawValue) else {
            return value.displayText
        }
        return mode.displayName
    }

    private func guardrailsDisplayName(for value: SettingsMutationValue) -> String {
        guard case .enumeration(let rawValue) = value,
              let guardrails = WheelAppleGuardrailsOption(rawValue: rawValue) else {
            return value.displayText
        }
        return guardrails.displayName
    }

    private func normalizeScaleIfNeeded(_ value: Double, for settingID: String) -> Double {
        guard settingID == "tabDock.hiddenScale" || settingID == "tabDock.shownScale" else {
            return value
        }
        if value >= 10 {
            return value / 100
        }
        return value
    }
}
