import Foundation

// MARK: - Agent

struct LettaAgent: Codable, Identifiable {
    let id: String
    let name: String
    let createdAt: String?
    let description: String?
    let metadata: [String: String]?
    let llmConfig: LLMConfig?
    let embeddingConfig: EmbeddingConfig?

    enum CodingKeys: String, CodingKey {
        case id, name, description, metadata
        case createdAt = "created_at"
        case llmConfig = "llm_config"
        case embeddingConfig = "embedding_config"
    }
}

struct LLMConfig: Codable {
    let model: String?
    let modelEndpointType: String?
    let modelEndpoint: String?
    let contextWindow: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case modelEndpointType = "model_endpoint_type"
        case modelEndpoint = "model_endpoint"
        case contextWindow = "context_window"
    }
}

struct EmbeddingConfig: Codable {
    let embeddingModel: String?
    let embeddingEndpointType: String?
    let embeddingEndpoint: String?
    let embeddingDim: Int?

    enum CodingKeys: String, CodingKey {
        case embeddingModel = "embedding_model"
        case embeddingEndpointType = "embedding_endpoint_type"
        case embeddingEndpoint = "embedding_endpoint"
        case embeddingDim = "embedding_dim"
    }
}

// MARK: - Create Agent Request

struct CreateAgentRequest: Codable {
    let name: String
    let description: String?
    let metadata: [String: String]?
    let system: String?
    let model: String?
    let embedding: String?
    let llmConfig: LLMConfig?
    let embeddingConfig: EmbeddingConfig?

    enum CodingKeys: String, CodingKey {
        case name, description, metadata, system, model, embedding
        case llmConfig = "llm_config"
        case embeddingConfig = "embedding_config"
    }
}

// MARK: - Message

struct LettaMessage: Codable, Identifiable {
    let id: String
    let role: String
    let text: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, role, text
        case createdAt = "created_at"
    }
}

struct SendMessageRequest: Codable {
    let messages: [MessageInput]
    let streamSteps: Bool?
    let streamTokens: Bool?

    enum CodingKeys: String, CodingKey {
        case messages
        case streamSteps = "stream_steps"
        case streamTokens = "stream_tokens"
    }
}

struct MessageInput: Codable {
    let role: String
    let content: String
}

// MARK: - Message Response

struct LettaMessageResponse: Codable {
    let messages: [LettaResponseMessage]
}

struct LettaResponseMessage: Codable, Identifiable {
    var id: String { UUID().uuidString }
    let messageType: String
    let assistantMessage: String?
    let internalMonologue: String?
    let functionCall: FunctionCallInfo?
    let functionReturn: String?

    enum CodingKeys: String, CodingKey {
        case messageType = "message_type"
        case assistantMessage = "assistant_message"
        case internalMonologue = "internal_monologue"
        case functionCall = "function_call"
        case functionReturn = "function_return"
    }
}

struct FunctionCallInfo: Codable {
    let name: String?
    let arguments: String?
}

// MARK: - Archival Memory

struct ArchivalMemoryEntry: Codable, Identifiable {
    let id: String
    let text: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, text
        case createdAt = "created_at"
    }
}

struct AddArchivalMemoryRequest: Codable {
    let text: String
}

// MARK: - Streaming Response

struct StreamingChunk: Codable {
    let messageType: String?
    let assistantMessage: String?
    let internalMonologue: String?

    enum CodingKeys: String, CodingKey {
        case messageType = "message_type"
        case assistantMessage = "assistant_message"
        case internalMonologue = "internal_monologue"
    }
}

// MARK: - Chat Message (Local)

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: MessageRole
    var content: String
    let timestamp: Date

    enum MessageRole: String {
        case user
        case assistant
        case system
        case thinking
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}
