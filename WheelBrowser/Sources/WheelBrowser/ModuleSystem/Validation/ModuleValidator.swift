import Foundation

/// Validates module manifests: schema checks, permission audits, and static JS analysis.
enum ModuleValidator {

    /// Validate a module manifest. Returns the manifest if valid, throws on failure.
    static func validate(_ manifest: ModuleManifest) throws -> ModuleManifest {
        try validateSchema(manifest)
        try validateTriggers(manifest)
        try validatePermissions(manifest)
        try validateCode(manifest)
        try validateContentRules(manifest)
        try validateResourceLimits(manifest)
        return manifest
    }

    // MARK: - Pass 1: Schema Validation

    private static func validateSchema(_ manifest: ModuleManifest) throws {
        guard !manifest.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ModuleValidationError(pass: 1, message: "Module name cannot be empty")
        }
        guard manifest.name.count <= 100 else {
            throw ModuleValidationError(pass: 1, message: "Module name exceeds 100 characters")
        }
        guard !manifest.description.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ModuleValidationError(pass: 1, message: "Module description cannot be empty")
        }
        guard manifest.version >= 1 else {
            throw ModuleValidationError(pass: 1, message: "Version must be >= 1")
        }
        guard !manifest.triggers.isEmpty else {
            throw ModuleValidationError(pass: 1, message: "Module must have at least one trigger")
        }

        // Must have at least one code/content section
        let hasContent = manifest.contentScript != nil
            || manifest.backgroundScript != nil
            || manifest.contentRules != nil
            || manifest.styles != nil
        guard hasContent else {
            throw ModuleValidationError(
                pass: 1,
                message: "Module must have at least one of: contentScript, backgroundScript, contentRules, or styles"
            )
        }
    }

    // MARK: - Pass 2: Trigger Validation

    private static func validateTriggers(_ manifest: ModuleManifest) throws {
        for trigger in manifest.triggers {
            switch trigger.type {
            case .pageLoad:
                guard let pattern = trigger.urlPattern, !pattern.isEmpty else {
                    throw ModuleValidationError(
                        pass: 2,
                        message: "pageLoad trigger requires a non-empty urlPattern"
                    )
                }
            case .schedule:
                guard let interval = trigger.intervalSeconds, interval >= 300 else {
                    throw ModuleValidationError(
                        pass: 2,
                        message: "schedule trigger requires intervalSeconds >= 300 (5 minutes)"
                    )
                }
            case .manual:
                // No additional requirements
                break
            case .always:
                // Only valid with contentRules
                guard manifest.contentRules != nil else {
                    throw ModuleValidationError(
                        pass: 2,
                        message: "'always' trigger is only valid with contentRules (no JS execution)"
                    )
                }
            }
        }
    }

    // MARK: - Pass 3: Permission Validation

    private static func validatePermissions(_ manifest: ModuleManifest) throws {
        // Check that permissions match actual module capabilities
        if manifest.contentScript != nil {
            // Content scripts should have at least page.read or dom permissions
            let hasDOMPermission = manifest.permissions.contains(where: {
                [.domQuery, .domModify, .domCSSInject, .domObserve, .pageRead].contains($0)
            })
            if !hasDOMPermission && manifest.styles == nil {
                throw ModuleValidationError(
                    pass: 3,
                    message: "contentScript requires at least one DOM or page permission",
                    suggestion: "Add 'page.read' or 'dom.query' to permissions"
                )
            }
        }

        if manifest.backgroundScript != nil && manifest.permissions.contains(.networkFetch) {
            // network.fetch requires domain restrictions (enforced at runtime too)
        }

        if manifest.contentRules != nil && !manifest.permissions.contains(.contentRules) {
            throw ModuleValidationError(
                pass: 3,
                message: "contentRules requires the 'content_rules' permission",
                suggestion: "Add 'content_rules' to permissions"
            )
        }

        if manifest.styles != nil && !manifest.permissions.contains(.domCSSInject) {
            throw ModuleValidationError(
                pass: 3,
                message: "styles requires the 'dom.css_inject' permission",
                suggestion: "Add 'dom.css_inject' to permissions"
            )
        }
    }

    // MARK: - Pass 4: Static JS Analysis

    private static let dangerousPatterns: [(pattern: String, description: String)] = [
        ("\\beval\\s*\\(", "Use of eval() is not allowed"),
        ("\\bnew\\s+Function\\s*\\(", "Use of new Function() is not allowed"),
        ("\\bimport\\s*\\(", "Dynamic import() is not allowed"),
        ("\\bdocument\\.cookie", "Direct cookie access is not allowed — use wheel.storage"),
        ("\\blocalStorage\\b", "Direct localStorage access is not allowed — use wheel.storage"),
        ("\\bsessionStorage\\b", "Direct sessionStorage access is not allowed — use wheel.storage"),
        ("\\bwindow\\.open\\b", "window.open is not allowed"),
        ("\\bXMLHttpRequest\\b", "XMLHttpRequest is not allowed — use wheel.fetch"),
        ("\\bfetch\\s*\\(", "Direct fetch() is not allowed — use wheel.fetch"),
        ("\\bWebSocket\\b", "WebSocket is not allowed"),
        ("\\bWorker\\b", "Worker is not allowed"),
    ]

    private static func validateCode(_ manifest: ModuleManifest) throws {
        if let script = manifest.contentScript {
            try analyzeScript(script, context: "contentScript")
        }
        if let script = manifest.backgroundScript {
            try analyzeScript(script, context: "backgroundScript")
        }
    }

    private static func analyzeScript(_ script: String, context: String) throws {
        for (pattern, description) in dangerousPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: script, range: NSRange(script.startIndex..., in: script)) != nil {
                throw ModuleValidationError(
                    pass: 4,
                    message: "\(context): \(description)",
                    suggestion: "Use the wheel.* API instead of direct browser APIs"
                )
            }
        }
    }

    // MARK: - Pass 5: Content Rules Validation

    private static func validateContentRules(_ manifest: ModuleManifest) throws {
        guard let rules = manifest.contentRules else { return }
        guard !rules.isEmpty else {
            throw ModuleValidationError(pass: 5, message: "contentRules array cannot be empty")
        }
        guard rules.count <= 50_000 else {
            throw ModuleValidationError(
                pass: 5,
                message: "contentRules exceeds 50,000 rule limit"
            )
        }

        // Basic structure validation — each rule needs trigger + action
        for (index, rule) in rules.enumerated() {
            guard rule["trigger"] != nil else {
                throw ModuleValidationError(
                    pass: 5,
                    message: "Content rule at index \(index) missing 'trigger'",
                    suggestion: "Each rule needs {\"trigger\": {...}, \"action\": {...}}"
                )
            }
            guard rule["action"] != nil else {
                throw ModuleValidationError(
                    pass: 5,
                    message: "Content rule at index \(index) missing 'action'",
                    suggestion: "Each rule needs {\"trigger\": {...}, \"action\": {...}}"
                )
            }
        }
    }

    // MARK: - Pass 6: Resource Limits

    private static func validateResourceLimits(_ manifest: ModuleManifest) throws {
        // Script size limits
        if let script = manifest.contentScript, script.utf8.count > 512_000 {
            throw ModuleValidationError(pass: 6, message: "contentScript exceeds 512KB size limit")
        }
        if let script = manifest.backgroundScript, script.utf8.count > 512_000 {
            throw ModuleValidationError(pass: 6, message: "backgroundScript exceeds 512KB size limit")
        }
        if let styles = manifest.styles {
            let totalCSS = styles.joined().utf8.count
            if totalCSS > 256_000 {
                throw ModuleValidationError(pass: 6, message: "Combined CSS exceeds 256KB size limit")
            }
        }
    }
}

// MARK: - Error

struct ModuleValidationError: LocalizedError {
    let pass: Int
    let message: String
    var suggestion: String?

    var errorDescription: String? {
        var result = "[Pass \(pass)] \(message)"
        if let suggestion {
            result += " (suggestion: \(suggestion))"
        }
        return result
    }
}
