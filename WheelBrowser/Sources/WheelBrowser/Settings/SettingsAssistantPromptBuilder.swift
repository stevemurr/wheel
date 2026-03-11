import Foundation

@MainActor
enum SettingsAssistantPromptBuilder {
    static let settingsTrackInstructions = """
    You are the Wheel Settings Assistant.

    You help users inspect and change Wheel app settings only.
    Stay within the supported settings surface. Do not invent settings, secrets, or unsupported controls.
    API keys, destructive debug actions, custom filter list CRUD, MCP port changes, and per-extension controls are out of scope.
    """

    static func routePrompt(
        userPrompt: String,
        registry: SettingsCapabilityRegistry
    ) -> String {
        """
        Classify the user's latest request for the Wheel Settings Assistant.

        Route definitions:
        - settings_report: the user wants to inspect, explain, compare, or report supported settings.
        - settings_mutation: the user wants to change, enable, disable, clear, reset, or configure supported settings.
        - general_chat: the user is asking for normal chat help rather than app settings control.
        - unsupported: the user is asking for app/system actions outside the supported settings surface.

        Only classify as settings_report or settings_mutation when the request is clearly about supported settings below.
        Return only structured data matching the schema.

        Supported settings:
        \(registry.supportedSettingsPrompt())

        User request:
        \(userPrompt)
        """
    }

    static func settingsPlanPrompt(
        userPrompt: String,
        route: SettingsAssistantRoute,
        registry: SettingsCapabilityRegistry
    ) -> String {
        """
        Produce a Wheel settings assistant response for the user's latest request.

        Rules:
        - Only use supported setting IDs shown below.
        - For pure reporting/explanation requests, return no actions and requiresConfirmation=false.
        - For mutation requests, return typed actions only for settings that should actually change.
        - Any mutation action requires requiresConfirmation=true.
        - Keep warnings concise and only include them when they materially matter.
        - If the request is partially unsupported, explain that in reply/warnings and only plan supported actions.
        - Use set_string with stringValue="" to clear ai.baseURL.
        - Use set_int with intValue=0 to reset ai.contextWindowOverride to the default.
        - For tab dock scales, prefer stored scale values like 1.15, but percentages like 115 are acceptable.
        - Never include API keys or hidden settings.
        - Return only structured data matching the schema.

        Current route: \(route.rawValue)

        Supported settings:
        \(registry.supportedSettingsPrompt())

        Current settings snapshot:
        \(registry.currentSettingsPrompt())

        User request:
        \(userPrompt)
        """
    }

    static func unsupportedReply(
        for decision: GeneratedSettingsRouteDecision,
        registry: SettingsCapabilityRegistry
    ) -> String {
        let supported = registry
            .descriptors()
            .map(\.displayName)
            .joined(separator: ", ")
        return """
        I can help with Wheel settings only in this panel. Supported areas are: \(supported).

        \(decision.reason)
        """
    }
}
