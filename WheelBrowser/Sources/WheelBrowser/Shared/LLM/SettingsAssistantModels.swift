import Foundation

enum SettingsAssistantRoute: String, CaseIterable, Sendable {
    case settingsReport = "settings_report"
    case settingsMutation = "settings_mutation"
    case generalChat = "general_chat"
    case unsupported
}

enum SettingsAssistantActionType: String, CaseIterable, Sendable {
    case setBool = "set_bool"
    case setString = "set_string"
    case setInt = "set_int"
    case setDouble = "set_double"
    case setEnum = "set_enum"
}

struct GeneratedSettingsRouteDecision: Codable, Sendable, WheelStructuredSpecProviding {
    let route: String
    let reason: String
    let confidence: Double
    let mentionedSettingIDs: [String]

    var normalizedRoute: SettingsAssistantRoute {
        switch route.lowercased() {
        case SettingsAssistantRoute.settingsReport.rawValue:
            return .settingsReport
        case SettingsAssistantRoute.settingsMutation.rawValue:
            return .settingsMutation
        case SettingsAssistantRoute.generalChat.rawValue:
            return .generalChat
        default:
            return .unsupported
        }
    }

    static let outputSchema = WheelOutputSchema.object(
        name: "GeneratedSettingsRouteDecision",
        description: "Classifies a settings assistant request.",
        properties: [
            WheelOutputSchema.property(
                "route",
                schema: WheelOutputSchema.enumeration(
                    name: "SettingsAssistantRoute",
                    cases: SettingsAssistantRoute.allCases.map(\.rawValue)
                ),
                description: "The request route."
            ),
            WheelOutputSchema.property(
                "reason",
                schema: WheelOutputSchema.string(minLength: 1),
                description: "One sentence explaining the route."
            ),
            WheelOutputSchema.property(
                "confidence",
                schema: WheelOutputSchema.number(minimum: 0, maximum: 1),
                description: "Confidence from 0 to 1."
            ),
            WheelOutputSchema.property(
                "mentionedSettingIDs",
                schema: WheelOutputSchema.array(
                    item: WheelOutputSchema.string(minLength: 1)
                ),
                description: "Supported setting IDs explicitly or strongly implied by the request.",
                optional: true
            ),
        ]
    )

    static let spec = structuredSpec { "Settings route: \($0.route)" }
}

struct GeneratedSettingsAction: Codable, Sendable {
    let actionType: String
    let settingID: String
    let boolValue: Bool?
    let stringValue: String?
    let intValue: Int?
    let doubleValue: Double?
    let enumValue: String?

    var normalizedActionType: SettingsAssistantActionType? {
        SettingsAssistantActionType(rawValue: actionType.lowercased())
    }

    static let outputSchema = WheelOutputSchema.object(
        name: "GeneratedSettingsAction",
        description: "A single typed settings change.",
        properties: [
            WheelOutputSchema.property(
                "actionType",
                schema: WheelOutputSchema.enumeration(
                    name: "SettingsAssistantActionType",
                    cases: SettingsAssistantActionType.allCases.map(\.rawValue)
                ),
                description: "The typed mutation to apply."
            ),
            WheelOutputSchema.property(
                "settingID",
                schema: WheelOutputSchema.string(minLength: 1),
                description: "The supported setting identifier to change."
            ),
            WheelOutputSchema.property(
                "boolValue",
                schema: WheelOutputSchema.boolean(),
                description: "Boolean payload for set_bool.",
                optional: true
            ),
            WheelOutputSchema.property(
                "stringValue",
                schema: WheelOutputSchema.string(),
                description: "String payload for set_string.",
                optional: true
            ),
            WheelOutputSchema.property(
                "intValue",
                schema: WheelOutputSchema.integer(),
                description: "Integer payload for set_int.",
                optional: true
            ),
            WheelOutputSchema.property(
                "doubleValue",
                schema: WheelOutputSchema.number(),
                description: "Double payload for set_double.",
                optional: true
            ),
            WheelOutputSchema.property(
                "enumValue",
                schema: WheelOutputSchema.string(minLength: 1),
                description: "Enum payload for set_enum.",
                optional: true
            ),
        ]
    )
}

struct GeneratedSettingsPlan: Codable, Sendable, WheelStructuredSpecProviding {
    let reply: String
    let warnings: [String]
    let actions: [GeneratedSettingsAction]
    let requiresConfirmation: Bool

    static let outputSchema = WheelOutputSchema.object(
        name: "GeneratedSettingsPlan",
        description: "A settings assistant reply plus optional typed mutations.",
        properties: [
            WheelOutputSchema.property(
                "reply",
                schema: WheelOutputSchema.string(minLength: 1),
                description: "The user-facing assistant reply in markdown."
            ),
            WheelOutputSchema.property(
                "warnings",
                schema: WheelOutputSchema.array(
                    item: WheelOutputSchema.string(minLength: 1),
                    maximumCount: 6
                ),
                description: "Warnings or caveats to show before confirmation.",
                optional: true
            ),
            WheelOutputSchema.property(
                "actions",
                schema: WheelOutputSchema.array(
                    item: GeneratedSettingsAction.outputSchema,
                    maximumCount: 12
                ),
                description: "Typed settings mutations to preview or apply.",
                optional: true
            ),
            WheelOutputSchema.property(
                "requiresConfirmation",
                schema: WheelOutputSchema.boolean(),
                description: "True when the reply proposes changes that require confirmation."
            ),
        ]
    )

    static let spec = structuredSpec { $0.reply }
}
