import Foundation
import WebKit

enum ExtensionCapability: String, Codable, CaseIterable, Sendable {
    case contentBlocking
    case contentScripts
}

enum ExtensionInstallSource: String, Codable, Sendable {
    case bundled
    case sideloaded
}

enum ContentBlockerSourceType: String, Codable, Sendable {
    case local
    case remote
}

struct ContentBlockerSpec: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let sourceType: ContentBlockerSourceType
    let path: String?
    let url: String?
    let defaultEnabled: Bool
}

enum ContentScriptInjectionTime: String, Codable, Sendable {
    case documentStart
    case documentEnd

    var webKitValue: WKUserScriptInjectionTime {
        switch self {
        case .documentStart:
            return .atDocumentStart
        case .documentEnd:
            return .atDocumentEnd
        }
    }
}

struct ContentScriptSpec: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let matches: [String]
    let excludeMatches: [String]
    let js: [String]
    let css: [String]
    let injectionTime: ContentScriptInjectionTime
    let allFrames: Bool
}

struct ExtensionManifest: Codable, Sendable {
    let id: String
    let name: String
    let version: String
    let defaultEnabled: Bool
    let capabilities: [ExtensionCapability]
    let contentBlockers: [ContentBlockerSpec]
    let contentScripts: [ContentScriptSpec]
}

struct InstalledExtensionState: Codable, Sendable {
    let id: String
    var isEnabled: Bool?
    var lastValidationError: String?
    var lastRuntimeError: String?
}

struct InstalledExtension: Identifiable, Sendable {
    let id: String
    let logicalID: String?
    let manifest: ExtensionManifest?
    let rootURL: URL
    let source: ExtensionInstallSource
    var isEnabled: Bool
    var lastValidationError: String?
    var lastRuntimeError: String?

    var displayName: String {
        manifest?.name ?? rootURL.lastPathComponent
    }

    var version: String {
        manifest?.version ?? "-"
    }

    var isValid: Bool {
        manifest != nil && lastValidationError == nil
    }

    var healthSummary: String {
        if let lastValidationError {
            return lastValidationError
        }
        if let lastRuntimeError {
            return lastRuntimeError
        }
        return "Ready"
    }
}

struct FilterListSubscriptionState: Codable, Identifiable, Sendable {
    let id: String
    let extensionID: String
    var name: String
    var sourceURL: String
    var isCustom: Bool
    var isEnabled: Bool
    var etag: String?
    var lastModified: String?
    var checksum: String?
    var lastCompiledChecksum: String?
    var lastCompiledIdentifier: String?
    var lastSuccessAt: Date?
    var lastError: String?
}

struct ExtensionRuntimeUserScript {
    let id: String
    let source: String
    let injectionTime: WKUserScriptInjectionTime
    let forMainFrameOnly: Bool
}

struct ExtensionRuntimeSnapshot {
    let revision: UUID
    let userScripts: [ExtensionRuntimeUserScript]
    let contentRuleLists: [WKContentRuleList]

    static let empty = ExtensionRuntimeSnapshot(
        revision: UUID(),
        userScripts: [],
        contentRuleLists: []
    )
}
