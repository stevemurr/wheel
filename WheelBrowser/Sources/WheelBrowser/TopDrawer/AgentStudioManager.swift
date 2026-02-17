import Foundation
import Combine

/// Manages the collection of agent configurations with persistence
@MainActor
class AgentStudioManager: ObservableObject {
    static let shared = AgentStudioManager()

    @Published private(set) var agents: [AgentConfig] = []
    @Published var activeAgentID: UUID?

    /// File URL for persisting agents
    private var agentsFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("WheelBrowser", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        return appDir.appendingPathComponent("agents.json")
    }

    private init() {
        loadAgents()

        // Ensure there's always a default agent
        if agents.isEmpty {
            let defaultAgent = AgentConfig.defaultAgent
            agents.append(defaultAgent)
            activeAgentID = defaultAgent.id
            Task { await saveAgents() }
        } else if activeAgentID == nil {
            // Set active agent to default or first available
            activeAgentID = agents.first(where: { $0.isDefault })?.id ?? agents.first?.id
        }
    }

    // MARK: - Public Methods

    /// Creates a new agent with default values
    func createAgent(
        name: String,
        icon: String = "sparkles",
        soul: String = "",
        skills: Set<AgentSkill> = [],
        model: String = "llama3.2:latest"
    ) {
        let newAgent = AgentConfig(
            name: name,
            icon: icon,
            soul: soul,
            skills: skills,
            model: model,
            isDefault: false
        )
        agents.append(newAgent)
        Task { await saveAgents() }
    }

    /// Updates an existing agent
    func updateAgent(_ agent: AgentConfig) {
        guard let index = agents.firstIndex(where: { $0.id == agent.id }) else { return }

        // If this agent is being set as default, clear other defaults
        if agent.isDefault {
            for i in agents.indices {
                agents[i].isDefault = false
            }
        }

        agents[index] = agent
        Task { await saveAgents() }
    }

    /// Deletes an agent by ID
    func deleteAgent(id: UUID) {
        // Prevent deleting the last agent
        guard agents.count > 1 else { return }

        // Prevent deleting the default agent (unless another exists)
        if let agent = agents.first(where: { $0.id == id }), agent.isDefault {
            // Find another agent to make default
            if let otherAgent = agents.first(where: { $0.id != id }) {
                var updatedOther = otherAgent
                updatedOther.isDefault = true
                updateAgent(updatedOther)
            }
        }

        agents.removeAll { $0.id == id }

        // Update active agent if deleted
        if activeAgentID == id {
            activeAgentID = agents.first(where: { $0.isDefault })?.id ?? agents.first?.id
        }

        Task { await saveAgents() }
    }

    /// Creates a duplicate of an existing agent
    func duplicateAgent(id: UUID) {
        guard let originalAgent = agents.first(where: { $0.id == id }) else { return }

        let duplicatedAgent = AgentConfig(
            name: "\(originalAgent.name) Copy",
            icon: originalAgent.icon,
            soul: originalAgent.soul,
            skills: originalAgent.skills,
            model: originalAgent.model,
            isDefault: false
        )

        agents.append(duplicatedAgent)
        Task { await saveAgents() }
    }

    /// Sets the active agent for the current workspace
    func setActiveAgent(id: UUID) {
        guard agents.contains(where: { $0.id == id }) else { return }
        activeAgentID = id
    }

    /// Returns the currently active agent configuration
    var activeAgent: AgentConfig? {
        guard let id = activeAgentID else { return agents.first }
        return agents.first { $0.id == id }
    }

    /// Returns the system prompt (soul) for the active agent
    var activeSystemPrompt: String {
        activeAgent?.soul ?? AgentConfig.defaultAgent.soul
    }

    // MARK: - Persistence

    private func loadAgents() {
        guard FileManager.default.fileExists(atPath: agentsFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: agentsFileURL)
            let decoded = try JSONDecoder().decode(AgentsData.self, from: data)
            agents = decoded.agents
            activeAgentID = decoded.activeAgentID
        } catch {
            print("Failed to load agents: \(error)")
        }
    }

    private func saveAgents() async {
        do {
            let data = AgentsData(agents: agents, activeAgentID: activeAgentID)
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: agentsFileURL, options: .atomic)
        } catch {
            print("Failed to save agents: \(error)")
        }
    }
}

// MARK: - Persistence Data Structure

private struct AgentsData: Codable {
    let agents: [AgentConfig]
    let activeAgentID: UUID?
}
