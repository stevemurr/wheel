import Foundation
import LanguageModelContextManagement

enum WheelModelProviderID: String, CaseIterable, Sendable {
    case apple
    case openAI = "openai"
    case vllm

    var displayName: String {
        switch self {
        case .apple:
            return "Apple"
        case .openAI:
            return "OpenAI"
        case .vllm:
            return "vLLM"
        }
    }

    var defaultModelID: String {
        switch self {
        case .apple:
            return "default"
        case .openAI:
            return "gpt-4.1-mini"
        case .vllm:
            return "meta-llama/Llama-3.2-3B-Instruct"
        }
    }

    var requiresBaseURL: Bool {
        switch self {
        case .apple:
            return false
        case .openAI, .vllm:
            return true
        }
    }

    var requiresAPIKey: Bool {
        self == .openAI
    }

    var supportsOptionalAPIKey: Bool {
        self == .vllm
    }

    var apiKeyLabel: String {
        switch self {
        case .apple:
            return "API Key"
        case .openAI:
            return "OpenAI API Key"
        case .vllm:
            return "vLLM API Key"
        }
    }
}

enum WheelAppleGuardrailsOption: String, CaseIterable, Sendable {
    case `default`
    case permissiveContentTransformations

    var displayName: String {
        switch self {
        case .default:
            return "Default"
        case .permissiveContentTransformations:
            return "Permissive Content Transformations"
        }
    }
}

struct WheelModelProfile: Equatable, Sendable {
    let providerID: WheelModelProviderID
    let modelID: String
    let baseURL: String?
    let contextWindowOverride: Int?
    let appleGuardrails: WheelAppleGuardrailsOption

    var displayName: String {
        "\(providerID.displayName) / \(modelID)"
    }
}

struct WheelModelCapabilities: Equatable, Sendable {
    let supportsTextGeneration: Bool
    let supportsTextStreaming: Bool
    let supportsStructuredOutput: Bool
    let supportsExactTokenEstimation: Bool
    let supportsLocaleHints: Bool

    init(_ runtimeCapabilities: RuntimeCapabilities = .init()) {
        self.supportsTextGeneration = runtimeCapabilities.supportsTextGeneration
        self.supportsTextStreaming = runtimeCapabilities.supportsTextStreaming
        self.supportsStructuredOutput = runtimeCapabilities.supportsStructuredOutput
        self.supportsExactTokenEstimation = runtimeCapabilities.supportsExactTokenEstimation
        self.supportsLocaleHints = runtimeCapabilities.supportsLocaleHints
    }
}

struct WheelModelAvailability: Equatable, Sendable {
    let isAvailable: Bool
    let reason: String?
    let capabilities: WheelModelCapabilities
    let displayName: String

    init(profile: WheelModelProfile, runtimeAvailability: RuntimeAvailability) {
        switch runtimeAvailability.status {
        case .available:
            self.isAvailable = true
            self.reason = nil
        case .unavailable(let reason):
            self.isAvailable = false
            self.reason = reason
        }
        self.capabilities = WheelModelCapabilities(runtimeAvailability.capabilities)
        self.displayName = profile.displayName
    }

    static func unavailable(profile: WheelModelProfile, reason: String) -> WheelModelAvailability {
        WheelModelAvailability(
            isAvailable: false,
            reason: reason,
            capabilities: WheelModelCapabilities(),
            displayName: profile.displayName
        )
    }

    static func unavailable(reason: String) -> WheelModelAvailability {
        unavailable(
            profile: WheelModelConfigurationProvider.shared.currentProfile(),
            reason: reason
        )
    }

    private init(
        isAvailable: Bool,
        reason: String?,
        capabilities: WheelModelCapabilities,
        displayName: String
    ) {
        self.isAvailable = isAvailable
        self.reason = reason
        self.capabilities = capabilities
        self.displayName = displayName
    }
}

protocol WheelModelSecretStoring: Sendable {
    func apiKey(for providerID: WheelModelProviderID) -> String?
    @discardableResult
    func setAPIKey(_ value: String?, for providerID: WheelModelProviderID) -> Bool
}

struct KeychainWheelModelSecretStore: WheelModelSecretStoring {
    static let shared = KeychainWheelModelSecretStore()

    func apiKey(for providerID: WheelModelProviderID) -> String? {
        switch providerID {
        case .apple:
            return nil
        case .openAI:
            return KeychainHelper.shared.retrieve(forKey: KeychainHelper.Keys.openAIAPIKey)
                ?? KeychainHelper.shared.retrieve(forKey: KeychainHelper.Keys.llmAPIKey)
        case .vllm:
            return KeychainHelper.shared.retrieve(forKey: KeychainHelper.Keys.vllmAPIKey)
        }
    }

    @discardableResult
    func setAPIKey(_ value: String?, for providerID: WheelModelProviderID) -> Bool {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard providerID != .apple else { return true }

        let key: String
        switch providerID {
        case .apple:
            return true
        case .openAI:
            key = KeychainHelper.Keys.openAIAPIKey
        case .vllm:
            key = KeychainHelper.Keys.vllmAPIKey
        }

        if normalized.isEmpty {
            return KeychainHelper.shared.delete(forKey: key)
        }
        return KeychainHelper.shared.save(normalized, forKey: key)
    }
}

struct WheelResolvedModelConfiguration: Equatable, Sendable {
    let profile: WheelModelProfile
    let threadRuntimeConfiguration: ThreadRuntimeConfiguration
}

protocol WheelModelConfigurationProviding: Sendable {
    func currentProfile() -> WheelModelProfile
    func resolvedConfiguration() -> WheelResolvedModelConfiguration
}

struct WheelModelConfigurationProvider: WheelModelConfigurationProviding {
    static let shared = WheelModelConfigurationProvider()

    let settings: AppSettings
    let secretStore: any WheelModelSecretStoring

    init(
        settings: AppSettings = .shared,
        secretStore: any WheelModelSecretStoring = KeychainWheelModelSecretStore.shared
    ) {
        self.settings = settings
        self.secretStore = secretStore
    }

    func currentProfile() -> WheelModelProfile {
        let providerID = WheelModelProviderID(rawValue: settings.aiProviderID) ?? .apple
        let trimmedModelID = settings.aiModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBaseURL = settings.aiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let guardrails = WheelAppleGuardrailsOption(rawValue: settings.aiAppleGuardrails) ?? .default

        return WheelModelProfile(
            providerID: providerID,
            modelID: trimmedModelID.isEmpty ? providerID.defaultModelID : trimmedModelID,
            baseURL: trimmedBaseURL.isEmpty ? nil : trimmedBaseURL,
            contextWindowOverride: settings.aiContextWindowOverride > 0 ? settings.aiContextWindowOverride : nil,
            appleGuardrails: guardrails
        )
    }

    func resolvedConfiguration() -> WheelResolvedModelConfiguration {
        let profile = currentProfile()
        let endpoint = makeInferenceEndpoint(from: profile)
        return WheelResolvedModelConfiguration(
            profile: profile,
            threadRuntimeConfiguration: ThreadRuntimeConfiguration(
                inference: endpoint,
                structuredOutput: nil
            )
        )
    }

    private func makeInferenceEndpoint(from profile: WheelModelProfile) -> ModelEndpoint {
        var options: [String: String] = [:]

        switch profile.providerID {
        case .apple:
            if profile.appleGuardrails != .default {
                options["guardrails"] = profile.appleGuardrails.rawValue
            }
        case .openAI:
            if let baseURL = profile.baseURL {
                options["baseURL"] = baseURL
            }
            if let apiKey = secretStore.apiKey(for: .openAI), apiKey.isEmpty == false {
                options["apiKey"] = apiKey
            }
        case .vllm:
            if let baseURL = profile.baseURL {
                options["baseURL"] = baseURL
            }
            if let apiKey = secretStore.apiKey(for: .vllm), apiKey.isEmpty == false {
                options["apiKey"] = apiKey
            }
        }

        return ModelEndpoint(
            backendID: profile.providerID.rawValue,
            modelID: profile.modelID,
            options: options,
            contextWindowOverride: profile.contextWindowOverride
        )
    }
}
