import Foundation

/// Skills that an agent can have enabled
enum AgentSkill: String, Codable, CaseIterable {
    case webResearch = "Web Research"
    case summarization = "Summarization"
    case codeAssist = "Code Assistance"
    case formFilling = "Form Filling"
    case priceComparison = "Price Comparison"
    case factChecking = "Fact Checking"

    /// SF Symbol icon for each skill
    var icon: String {
        switch self {
        case .webResearch: return "magnifyingglass"
        case .summarization: return "doc.text"
        case .codeAssist: return "chevron.left.forwardslash.chevron.right"
        case .formFilling: return "pencil.and.list.clipboard"
        case .priceComparison: return "dollarsign.arrow.trianglehead.counterclockwise.rotate.90"
        case .factChecking: return "checkmark.shield"
        }
    }

    /// Short description of what each skill does
    var description: String {
        switch self {
        case .webResearch: return "Search and analyze web content"
        case .summarization: return "Condense long content into key points"
        case .codeAssist: return "Help with code understanding and debugging"
        case .formFilling: return "Assist with filling out web forms"
        case .priceComparison: return "Compare prices across websites"
        case .factChecking: return "Verify claims and find sources"
        }
    }
}

/// Represents a configured AI agent with personality and skills
struct AgentConfig: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var icon: String  // SF Symbol name
    var soul: String  // System prompt / personality description (like OpenClaw's SOUL.md)
    var skills: Set<AgentSkill>  // Enabled capabilities
    var model: String  // e.g., "claude-sonnet", "claude-opus"
    var createdAt: Date
    var isDefault: Bool

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "sparkles",
        soul: String = "",
        skills: Set<AgentSkill> = [],
        model: String = "llama3.2:latest",
        createdAt: Date = Date(),
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.soul = soul
        self.skills = skills
        self.model = model
        self.createdAt = createdAt
        self.isDefault = isDefault
    }

    static func == (lhs: AgentConfig, rhs: AgentConfig) -> Bool {
        lhs.id == rhs.id
    }

    /// Creates the default "General Assistant" agent
    static var defaultAgent: AgentConfig {
        AgentConfig(
            name: "General Assistant",
            icon: "sparkles",
            soul: """
            You are a helpful AI assistant integrated into a web browser called Wheel.

            Your role is to help users:
            - Understand and summarize web page content
            - Answer questions about pages they're viewing
            - Help with research and information gathering

            When the user asks about the current page, use the page context provided in the message.
            Be concise but helpful. Focus on the most relevant information for the user's question.
            """,
            skills: Set(AgentSkill.allCases),
            model: "llama3.2:latest",
            isDefault: true
        )
    }
}

// MARK: - Available Agent Icons

extension AgentConfig {
    /// Predefined icons for agent selection
    static let availableIcons: [String] = [
        "sparkles",
        "brain",
        "lightbulb",
        "wand.and.stars",
        "cpu",
        "network",
        "text.bubble",
        "bubble.left.and.bubble.right",
        "person.fill.questionmark",
        "questionmark.circle",
        "magnifyingglass",
        "doc.text.magnifyingglass",
        "book",
        "graduationcap",
        "briefcase",
        "chart.bar",
        "cart",
        "dollarsign.circle",
        "creditcard",
        "globe",
        "paperplane",
        "shield.checkered",
        "lock.shield",
        "hammer",
        "wrench.and.screwdriver",
        "terminal",
        "chevron.left.forwardslash.chevron.right",
        "paintbrush",
        "camera",
        "photo"
    ]

    /// Available model options
    static let availableModels: [String] = [
        "llama3.2:latest",
        "claude-sonnet",
        "claude-opus",
        "gpt-4",
        "gpt-4-turbo",
        "mistral"
    ]
}
