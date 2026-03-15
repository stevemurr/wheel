import Foundation
import Testing
@testable import WheelBrowser

@Suite("Wheel Structured Models")
struct WheelStructuredModelTests {
    @Test("Chat response spec decodes Codable JSON")
    func chatResponseSpecDecodes() throws {
        let value = GeneratedChatAssistantResponse(
            answer: "Hello, world.",
            thinking: "I summarized the key point before answering.",
            toolCalls: [
                GeneratedChatToolCall(
                    name: "web.search",
                    inputSummary: "site:example.com release notes",
                    outputSummary: "Found the release notes page."
                )
            ],
            suggestions: ["What changed?", "Show me the sources."]
        )

        let decoded = try decode(value, with: GeneratedChatAssistantResponse.spec)

        #expect(decoded.answer == value.answer)
        #expect(decoded.thinking == value.thinking)
        #expect(decoded.toolCalls == value.toolCalls)
        #expect(decoded.suggestions == value.suggestions)
    }

    @Test("Chat response spec tolerates wrapped payloads and string suggestions")
    func chatResponseSpecDecodesWrappedMalformedSuggestions() throws {
        let payload = #"{"response":{"answer":"Hello, world.","suggestions":"- What changed?\n- Show me the sources."}}"#

        let decoded = try decodeJSON(payload, with: GeneratedChatAssistantResponse.spec)

        #expect(decoded.answer == "Hello, world.")
        #expect(decoded.suggestions == ["- What changed?", "- Show me the sources."])
        #expect(decoded.normalizedSuggestions == ["What changed?", "Show me the sources."])
    }

    @Test("Chat response spec decodes optional thinking and tool call summaries")
    func chatResponseSpecDecodesThinkingAndToolCalls() throws {
        let payload = #"{"answer":"Hello, world.","thinking":"Checked the latest release notes.","toolCalls":[{"name":"web.search","inputSummary":"latest release notes","outputSummary":"Matched the official docs page."}]}"#

        let decoded = try decodeJSON(payload, with: GeneratedChatAssistantResponse.spec)

        #expect(decoded.answer == "Hello, world.")
        #expect(decoded.normalizedThinking == "Checked the latest release notes.")
        #expect(decoded.toolCalls == [
            GeneratedChatToolCall(
                name: "web.search",
                inputSummary: "latest release notes",
                outputSummary: "Matched the official docs page."
            )
        ])
    }

    @Test("Summary response spec decodes Codable JSON")
    func summaryResponseSpecDecodes() throws {
        let value = GeneratedSummaryResponse(summary: "A concise summary.")

        let decoded = try decode(value, with: GeneratedSummaryResponse.spec)

        #expect(decoded.summary == value.summary)
    }

    @Test("Summary response spec unwraps response envelopes")
    func summaryResponseSpecDecodesWrappedPayload() throws {
        let payload = #"{"response":{"summary":"A concise summary."}}"#

        let decoded = try decodeJSON(payload, with: GeneratedSummaryResponse.spec)

        #expect(decoded.summary == "A concise summary.")
    }

    @Test("Agent intent spec decodes Codable JSON")
    func agentIntentSpecDecodes() throws {
        let value = GeneratedAgentTaskIntent(
            seedURL: "https://news.ycombinator.com/news",
            sourceHosts: ["news.ycombinator.com"],
            targetHosts: ["arxiv.org"],
            pageLimit: 3,
            outputLimit: 5,
            requiresUniqueURLs: true,
            requiresPerItemSummaries: true,
            collectionMode: "paginated_links",
            canonicalizationStrategy: "arxiv",
            collectionStrategy: "hacker_news_story_links",
            sourcePageIdentityStrategy: "hacker_news_news_pages",
            finalResponseFormat: "markdown_table"
        )

        let decoded = try decode(value, with: GeneratedAgentTaskIntent.spec)

        #expect(decoded.seedURL == value.seedURL)
        #expect(decoded.sourceHosts == value.sourceHosts)
        #expect(decoded.finalResponseFormat == value.finalResponseFormat)
    }

    @Test("Agent decision spec decodes Codable JSON")
    func agentDecisionSpecDecodes() throws {
        let value = GeneratedAgentDecision(
            thought: "Read the current result list first.",
            action: GeneratedAgentAction(
                actionType: "read_links",
                elementId: nil,
                text: nil,
                url: nil,
                scrollDirection: nil,
                modifiers: nil,
                tabIndex: nil,
                reason: nil,
                waitSeconds: nil,
                summary: nil
            )
        )

        let decoded = try decode(value, with: GeneratedAgentDecision.spec)

        #expect(decoded.thought == value.thought)
        #expect(decoded.action.actionType == value.action.actionType)
    }

    @Test("Completion evaluation spec decodes Codable JSON")
    func completionEvaluationSpecDecodes() throws {
        let value = GeneratedAgentCompletionEvaluation(
            isComplete: false,
            reason: "The answer is missing per-item summaries.",
            recommendedNextStep: "Open each remaining item and summarize it."
        )

        let decoded = try decode(value, with: GeneratedAgentCompletionEvaluation.spec)

        #expect(decoded.isComplete == value.isComplete)
        #expect(decoded.reason == value.reason)
        #expect(decoded.recommendedNextStep == value.recommendedNextStep)
    }

    @Test("Widget plan spec decodes Codable JSON")
    func widgetPlanSpecDecodes() throws {
        let value = GeneratedWidgetPlan(
            title: "Greeting",
            widgetType: "text",
            source: GeneratedWidgetSourcePlan(
                kind: "literalText",
                url: nil,
                jsonPath: nil,
                resultShape: nil,
                sortBy: nil,
                sortAscending: nil,
                limit: nil,
                timeZones: nil
            ),
            refreshSeconds: 300,
            prompt: "Show hello",
            text: GeneratedWidgetTextPlan(
                contentField: nil,
                literalContent: "Hello",
                markdown: false,
                showTimeZone: nil,
                includeSeconds: nil
            ),
            metric: nil,
            list: nil,
            table: nil,
            chart: nil
        )

        let decoded = try decode(value, with: GeneratedWidgetPlan.spec)

        #expect(decoded.title == value.title)
        #expect(decoded.widgetType == value.widgetType)
        #expect(decoded.text?.literalContent == value.text?.literalContent)
    }

    @Test("Settings route decision spec decodes Codable JSON")
    func settingsRouteDecisionSpecDecodes() throws {
        let value = GeneratedSettingsRouteDecision(
            route: SettingsAssistantRoute.settingsMutation.rawValue,
            reason: "The user asked to enable Semantic Search.",
            confidence: 0.96,
            mentionedSettingIDs: ["semanticSearch.enabled"]
        )

        let decoded = try decode(value, with: GeneratedSettingsRouteDecision.spec)

        #expect(decoded.route == value.route)
        #expect(decoded.mentionedSettingIDs == value.mentionedSettingIDs)
        #expect(decoded.normalizedRoute == .settingsMutation)
    }

    @Test("Settings plan spec decodes wrapped payloads")
    func settingsPlanSpecDecodesWrappedPayload() throws {
        let payload = """
        {"response":{"reply":"I can turn Semantic Search on.","warnings":["This reinitializes the local search backend."],"actions":[{"actionType":"set_bool","settingID":"semanticSearch.enabled","boolValue":true}],"requiresConfirmation":true}}
        """

        let decoded = try decodeJSON(payload, with: GeneratedSettingsPlan.spec)

        #expect(decoded.reply == "I can turn Semantic Search on.")
        #expect(decoded.warnings == ["This reinitializes the local search backend."])
        #expect(decoded.actions.count == 1)
        #expect(decoded.actions[0].normalizedActionType == .setBool)
        #expect(decoded.actions[0].settingID == "semanticSearch.enabled")
        #expect(decoded.requiresConfirmation)
    }

    @Test("Streaming extractor returns partial top-level string values")
    func partialStringExtraction() {
        let partial = #"{"answer":"Hello wor"#

        let extracted = WheelStructuredJSONExtractor.topLevelStringValue(
            named: "answer",
            in: partial
        )

        #expect(extracted == "Hello wor")
    }

    @Test("Streaming extractor normalizes wrapped JSON bodies")
    func normalizesWrappedJSON() {
        let wrapped = """
        ```json
        {"summary":"A concise result."}
        ```
        """

        #expect(
            WheelStructuredJSONExtractor.normalizedJSONObject(in: wrapped)
                == #"{"summary":"A concise result."}"#
        )
    }

    @Test("Streaming extractor can unwrap legacy response envelopes")
    func unwrapsLegacyResponseEnvelope() {
        let wrapped = #"{"response":{"answer":"Hello!","suggestions":[]}}"#

        let candidates = WheelStructuredJSONExtractor.candidateJSONObjectStrings(in: wrapped)

        #expect(candidates.contains(#"{"response":{"answer":"Hello!","suggestions":[]}}"#))
        #expect(candidates.contains(#"{"answer":"Hello!","suggestions":[]}"#))
    }

    @Test("Stream accumulator handles cumulative snapshots and fragments")
    func streamAccumulatorMergesSnapshotsAndFragments() {
        let cumulative = WheelStructuredStreamAccumulator.merge(
            existing: "{\"answer\":\"Hello",
            incoming: "{\"answer\":\"Hello world"
        )
        let appended = WheelStructuredStreamAccumulator.merge(
            existing: "Hello",
            incoming: " world"
        )

        #expect(cumulative == "{\"answer\":\"Hello world")
        #expect(appended == "Hello world")
    }

    @Test("Apple compatibility removes string length constraints recursively")
    func removesStringLengthConstraints() {
        let sanitized = WheelOutputSchema.removingStringLengthConstraints(
            from: GeneratedChatAssistantResponse.outputSchema
        )

        guard case .object(let object) = sanitized else {
            Issue.record("Expected object schema")
            return
        }

        let answerProperty = object.properties.first { $0.name == "answer" }
        let suggestionsProperty = object.properties.first { $0.name == "suggestions" }

        guard case .string(let answerConstraints) = answerProperty?.schema else {
            Issue.record("Expected answer to remain a string")
            return
        }
        #expect(answerConstraints.minLength == nil)
        #expect(answerConstraints.maxLength == nil)

        guard case .array(let arrayConstraints) = suggestionsProperty?.schema,
              case .string(let itemConstraints) = arrayConstraints.item else {
            Issue.record("Expected suggestions to remain an array of strings")
            return
        }
        #expect(itemConstraints.minLength == nil)
        #expect(itemConstraints.maxLength == nil)
    }

    @Test("Prompt renderer describes top-level structured properties")
    func promptRendererUsesTopLevelSchema() {
        let rendered = WheelOutputSchemaPromptRenderer.render(
            schema: GeneratedChatAssistantResponse.outputSchema
        )

        #expect(rendered.contains(#""answer": { type: string, minLength: 1 }"#))
        #expect(rendered.contains(#""suggestions (optional)": { type: array"#))
        #expect(rendered.contains(#""response":"#) == false)
    }

    private func decode<Value: Encodable & Sendable>(
        _ value: Value,
        with spec: StructuredOutputSpec<Value>
    ) throws -> Value {
        let data = try JSONEncoder().encode(value)
        return try spec.decode(data)
    }

    private func decodeJSON<Value: Sendable>(
        _ json: String,
        with spec: StructuredOutputSpec<Value>
    ) throws -> Value {
        try spec.decode(Data(json.utf8))
    }
}
