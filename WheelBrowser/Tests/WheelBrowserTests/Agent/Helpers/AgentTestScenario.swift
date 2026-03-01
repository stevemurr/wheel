import Foundation

/// Defines a test scenario for live agent testing
struct AgentTestScenario: Codable, Sendable {
    /// Unique name for this scenario (used as test identifier)
    let name: String
    /// Human-readable description of what this scenario tests
    let description: String
    /// Starting URL to navigate to before running the agent
    let startURL: String
    /// The task to give the agent
    let task: String
    /// Maximum steps allowed (default: 30)
    let maxSteps: Int?
    /// Timeout in seconds (default: 120)
    let timeout: TimeInterval?
    /// How to evaluate success
    let successCriteria: SuccessCriteria
    /// Tags for filtering (e.g., "search", "navigation", "form")
    let tags: [String]?
}

/// Criteria for evaluating whether an agent test scenario passed
struct SuccessCriteria: Codable, Sendable {
    /// Agent must report success (done() called)
    let requireAgentSuccess: Bool
    /// URL must contain this string after completion
    let urlContains: String?
    /// Page title must contain this string (case-insensitive)
    let titleContains: String?
    /// Page content must contain this text (case-insensitive)
    let pageContains: String?
    /// Agent summary must contain this string (case-insensitive)
    let summaryContains: String?
    /// Maximum steps to consider "efficient" (soft metric, logged but doesn't fail)
    let maxExpectedSteps: Int?
}

// MARK: - Fixture Loading

extension AgentTestScenario {
    /// Load a scenario from a JSON file by name (without extension)
    static func load(named name: String, from directory: URL) throws -> AgentTestScenario {
        let fileURL = directory.appendingPathComponent("\(name).json")
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(AgentTestScenario.self, from: data)
    }

    /// Load all scenarios from JSON files in a directory
    static func loadAll(from directory: URL) throws -> [AgentTestScenario] {
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try files.map { fileURL in
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(AgentTestScenario.self, from: data)
        }
    }

    /// List all fixture names (without extension) in a directory
    static func allFixtureNames(in directory: URL) -> [String] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    /// Get the fixtures directory relative to the test bundle
    static var fixturesDirectory: URL {
        // Walk up from this source file to find the Fixtures directory
        let thisFile = URL(fileURLWithPath: #filePath)
        let agentDir = thisFile.deletingLastPathComponent().deletingLastPathComponent()
        return agentDir.appendingPathComponent("Fixtures")
    }
}
