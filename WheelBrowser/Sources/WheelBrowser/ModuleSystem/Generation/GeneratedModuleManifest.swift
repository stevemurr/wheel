import Foundation
import FoundationModels

@Generable(description: "A browser module manifest.")
struct GeneratedModuleManifest: Sendable {
    let name: String
    let description: String
    let permissions: [String]
    let triggers: [GeneratedModuleTrigger]
    let contentRules: GeneratedContent?
    let styles: [String]?
    let contentScript: String?
    let backgroundScript: String?
    let isEnabled: Bool?

    init(
        name: String,
        description: String,
        permissions: [String],
        triggers: [GeneratedModuleTrigger],
        contentRules: GeneratedContent?,
        styles: [String]?,
        contentScript: String?,
        backgroundScript: String?,
        isEnabled: Bool?
    ) {
        self.name = name
        self.description = description
        self.permissions = permissions
        self.triggers = triggers
        self.contentRules = contentRules
        self.styles = styles
        self.contentScript = contentScript
        self.backgroundScript = backgroundScript
        self.isEnabled = isEnabled
    }

    func toManifest(preserving currentManifest: ModuleManifest? = nil) throws -> ModuleManifest {
        let permissions = try permissions.map { permissionRaw in
            guard let permission = ModulePermission(rawValue: permissionRaw) else {
                throw ModuleGenerationError.parseFailed("Unknown module permission: \(permissionRaw)")
            }
            return permission
        }

        let triggers = try triggers.map { try $0.toModuleTrigger() }
        let now = Date()

        return ModuleManifest(
            id: currentManifest?.id ?? UUID(),
            name: name,
            description: description,
            version: currentManifest.map { $0.version + 1 } ?? 1,
            permissions: permissions,
            triggers: triggers,
            contentRules: try GeneratedContentBridge.dictionaryArray(from: contentRules),
            styles: styles,
            contentScript: contentScript,
            backgroundScript: backgroundScript,
            isEnabled: isEnabled ?? currentManifest?.isEnabled ?? true,
            createdAt: currentManifest?.createdAt ?? now,
            updatedAt: now
        )
    }
}

@Generable(description: "A single module trigger.")
struct GeneratedModuleTrigger: Sendable {
    let type: String
    let urlPattern: String?
    let intervalSeconds: Int?

    init(type: String, urlPattern: String?, intervalSeconds: Int?) {
        self.type = type
        self.urlPattern = urlPattern
        self.intervalSeconds = intervalSeconds
    }

    func toModuleTrigger() throws -> ModuleTrigger {
        guard let triggerType = ModuleTrigger.TriggerType(rawValue: type) else {
            throw ModuleGenerationError.parseFailed("Unknown module trigger type: \(type)")
        }

        return ModuleTrigger(
            type: triggerType,
            urlPattern: urlPattern,
            intervalSeconds: intervalSeconds
        )
    }
}
