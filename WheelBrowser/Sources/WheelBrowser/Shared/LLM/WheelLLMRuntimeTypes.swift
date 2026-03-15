import Foundation

struct BudgetPolicy: Equatable, Sendable, Codable {
    var reservedOutputTokens: Int
    var defaultContextWindowTokens: Int
    var preemptiveCompactionFraction: Double
    var emergencyFraction: Double
    var heuristicSafetyMultiplier: Double

    init(
        reservedOutputTokens: Int = 1024,
        defaultContextWindowTokens: Int = 8192,
        preemptiveCompactionFraction: Double = 0.85,
        emergencyFraction: Double = 0.95,
        heuristicSafetyMultiplier: Double = 1.1
    ) {
        self.reservedOutputTokens = reservedOutputTokens
        self.defaultContextWindowTokens = defaultContextWindowTokens
        self.preemptiveCompactionFraction = preemptiveCompactionFraction
        self.emergencyFraction = emergencyFraction
        self.heuristicSafetyMultiplier = heuristicSafetyMultiplier
    }
}

struct RuntimeCapabilities: Equatable, Sendable, Codable {
    var supportsTextGeneration: Bool
    var supportsTextStreaming: Bool
    var supportsStructuredOutput: Bool
    var supportsExactTokenEstimation: Bool
    var supportsLocaleHints: Bool

    init(
        supportsTextGeneration: Bool = false,
        supportsTextStreaming: Bool = false,
        supportsStructuredOutput: Bool = false,
        supportsExactTokenEstimation: Bool = false,
        supportsLocaleHints: Bool = false
    ) {
        self.supportsTextGeneration = supportsTextGeneration
        self.supportsTextStreaming = supportsTextStreaming
        self.supportsStructuredOutput = supportsStructuredOutput
        self.supportsExactTokenEstimation = supportsExactTokenEstimation
        self.supportsLocaleHints = supportsLocaleHints
    }
}

struct RuntimeAvailability: Equatable, Sendable, Codable {
    enum Status: Equatable, Sendable, Codable {
        case available
        case unavailable(reason: String)
    }

    var status: Status
    var capabilities: RuntimeCapabilities

    init(
        status: Status,
        capabilities: RuntimeCapabilities = RuntimeCapabilities()
    ) {
        self.status = status
        self.capabilities = capabilities
    }
}

struct ModelEndpoint: Equatable, Sendable, Codable {
    let backendID: String
    let modelID: String
    var options: [String: String]
    var contextWindowOverride: Int?

    init(
        backendID: String,
        modelID: String,
        options: [String: String] = [:],
        contextWindowOverride: Int? = nil
    ) {
        self.backendID = backendID
        self.modelID = modelID
        self.options = options
        self.contextWindowOverride = contextWindowOverride
    }
}

struct ThreadRuntimeConfiguration: Equatable, Sendable, Codable {
    let inference: ModelEndpoint
    let structuredOutput: ModelEndpoint?

    init(
        inference: ModelEndpoint,
        structuredOutput: ModelEndpoint? = nil
    ) {
        self.inference = inference
        self.structuredOutput = structuredOutput
    }
}

struct WheelTranscriptTruncation: Equatable, Sendable, Codable {
    let droppedTurnCount: Int
    let retainedTurnCount: Int
    let estimatedInputTokens: Int
    let contextWindowTokens: Int
}

struct BudgetReport: Equatable, Sendable, Codable {
    let contextWindowTokens: Int
    let estimatedInputTokens: Int
    let reservedOutputTokens: Int
    let projectedTotalTokens: Int

    init(
        contextWindowTokens: Int,
        estimatedInputTokens: Int,
        reservedOutputTokens: Int,
        projectedTotalTokens: Int
    ) {
        self.contextWindowTokens = contextWindowTokens
        self.estimatedInputTokens = estimatedInputTokens
        self.reservedOutputTokens = reservedOutputTokens
        self.projectedTotalTokens = projectedTotalTokens
    }
}

struct CompactionReport: Equatable, Sendable, Codable {}
struct BridgeReport: Equatable, Sendable, Codable {}

struct SessionDiagnostics: Equatable, Sendable, Codable {
    let sessionID: String
    let windowIndex: Int
    let lastBudget: BudgetReport?
    let lastCompaction: CompactionReport?
    let lastBridge: BridgeReport?
    let turnCount: Int
    let durableMemoryCount: Int
    let blobCount: Int
}

enum RuntimeError: Error, Equatable, Sendable {
    case unavailable(String)
    case unsupportedCapability(String)
    case unsupportedLocale(String)
    case contextOverflow(String)
    case refusal(String)
    case generationFailed(String)
    case transportFailed(String)
}

enum ContextManagerError: Error, Sendable {
    case threadNotFound(String)
    case persistenceFailed(String)
    case budgetExhausted(SessionDiagnostics)
}

struct WheelConversationTurn: Identifiable, Equatable, Sendable, Codable {
    enum Role: String, Equatable, Sendable, Codable {
        case user
        case assistant
        case system
    }

    let id: UUID
    let role: Role
    let text: String
    let createdAt: Date
    let priority: Int
    let tags: [String]

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        createdAt: Date = Date(),
        priority: Int,
        tags: [String] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.priority = priority
        self.tags = tags
    }
}
