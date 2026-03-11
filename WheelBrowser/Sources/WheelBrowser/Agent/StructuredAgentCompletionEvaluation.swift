import Foundation

enum AgentCompletionEvaluationPrompt {
    static let instructions = """
    You evaluate whether a browser automation agent's proposed final answer fully satisfies the user's task.

    Decide semantically from the task, the structured intent, the collected evidence, and the current page observation.
    Do not use shallow heuristics like page appearance alone. Focus on whether the requested deliverable is actually present.
    Reject answers that omit requested summaries, counts, filters, links, or output format.
    If the user asked for a fixed number of items, reject answers with too few items unless the evidence clearly shows the source is exhausted and the answer explicitly explains the shortfall.
    If per-item summaries are required, each returned item must include its own actual summary, not just a title or URL.
    If the user requested a markdown table, reject non-table answers.
    For paginated collection tasks, reject completion if the requested source-page budget has not been met and more requested pages remain available.

    Return only structured data matching the schema.
    """

    static func buildPrompt(
        task: String,
        intent: AgentTaskIntent,
        collectionSummary: String?,
        observation: ReducedPageObservation,
        proposedSummary: String
    ) -> String {
        var lines: [String] = []
        lines.append("TASK: \(task)")
        lines.append("")
        lines.append("STRUCTURED INTENT:")
        lines.append("Collection mode: \(intent.collectionMode.rawValue)")
        if let seedURL = intent.seedURL {
            lines.append("Seed URL: \(seedURL)")
        }
        if let pageLimit = intent.pageLimit {
            lines.append("Requested page limit: \(pageLimit)")
        }
        if let outputLimit = intent.outputLimit {
            lines.append("Requested final item count: \(outputLimit)")
        }
        lines.append("Requires unique URLs: \(intent.requiresUniqueURLs ? "yes" : "no")")
        lines.append("Requires per-item summaries: \(intent.requiresPerItemSummaries ? "yes" : "no")")
        lines.append("Final response format: \(intent.finalResponseFormat.rawValue)")
        if !intent.sourceHosts.isEmpty {
            lines.append("Source hosts: \(intent.sourceHosts.joined(separator: ", "))")
        }
        if !intent.targetHosts.isEmpty {
            lines.append("Target hosts: \(intent.targetHosts.joined(separator: ", "))")
        }

        if let collectionSummary, !collectionSummary.isEmpty {
            lines.append("")
            lines.append("COLLECTION STATE:")
            lines.append(collectionSummary)
        }

        lines.append("")
        lines.append("CURRENT PAGE:")
        lines.append(observation.textRepresentation)
        lines.append("")
        lines.append("PROPOSED FINAL ANSWER:")
        lines.append(proposedSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(empty)" : proposedSummary)
        lines.append("")
        lines.append("Does the proposed final answer fully satisfy the task?")
        return lines.joined(separator: "\n")
    }
}

struct AgentCompletionEvaluation: Sendable {
    let isComplete: Bool
    let reason: String
    let recommendedNextStep: String?
}

struct GeneratedAgentCompletionEvaluation: Codable, Sendable, WheelStructuredSpecProviding {
    let isComplete: Bool

    let reason: String

    let recommendedNextStep: String?

    init(isComplete: Bool, reason: String, recommendedNextStep: String?) {
        self.isComplete = isComplete
        self.reason = reason
        self.recommendedNextStep = recommendedNextStep
    }

    func toEvaluation() throws -> AgentCompletionEvaluation {
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedReason.isEmpty else {
            throw AgentError.invalidLLMResponse("Structured completion evaluation omitted reason")
        }

        return AgentCompletionEvaluation(
            isComplete: isComplete,
            reason: normalizedReason,
            recommendedNextStep: {
                let normalized = recommendedNextStep?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return normalized.isEmpty ? nil : normalized
            }()
        )
    }

    static let outputSchema = WheelOutputSchema.object(
        name: "GeneratedAgentCompletionEvaluation",
        description: "Whether the proposed final answer fully satisfies the browser task.",
        properties: [
            WheelOutputSchema.property(
                "isComplete",
                schema: WheelOutputSchema.boolean(),
                description: "True if the proposed final answer fully satisfies the user's request."
            ),
            WheelOutputSchema.property(
                "reason",
                schema: WheelOutputSchema.string(minLength: 1),
                description: "Short explanation for accepting or rejecting the proposed final answer."
            ),
            WheelOutputSchema.property(
                "recommendedNextStep",
                schema: WheelOutputSchema.string(minLength: 1),
                description: "Concrete next step when incomplete.",
                optional: true
            ),
        ]
    )

    static let spec = structuredSpec { $0.reason }
}
