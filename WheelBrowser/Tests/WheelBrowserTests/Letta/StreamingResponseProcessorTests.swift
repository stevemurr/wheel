import Testing
@testable import WheelBrowser

@Suite("StreamingResponseProcessor Tests")
struct StreamingResponseProcessorTests {
    let processor = StreamingResponseProcessor()

    // MARK: - Basic content extraction

    @Test("Extracts content chunk from standard SSE event")
    func extractContent() {
        let json = #"{"choices":[{"delta":{"content":"Hello"},"index":0}]}"#
        let chunks = processor.processSSEEvent(json)
        #expect(chunks.count == 1)
        if case .content(let text) = chunks.first {
            #expect(text == "Hello")
        } else {
            Issue.record("Expected .content chunk")
        }
    }

    @Test("Extracts thinking chunk from Claude format")
    func extractThinkingClaude() {
        let json = #"{"choices":[{"delta":{"thinking":"Let me analyze..."},"index":0}]}"#
        let chunks = processor.processSSEEvent(json)
        #expect(chunks.count == 1)
        if case .thinking(let text) = chunks.first {
            #expect(text == "Let me analyze...")
        } else {
            Issue.record("Expected .thinking chunk")
        }
    }

    @Test("Extracts thinking chunk from OpenAI reasoning_content format")
    func extractThinkingOpenAI() {
        let json = #"{"choices":[{"delta":{"reasoning_content":"Step 1..."},"index":0}]}"#
        let chunks = processor.processSSEEvent(json)
        #expect(chunks.count == 1)
        if case .thinking(let text) = chunks.first {
            #expect(text == "Step 1...")
        } else {
            Issue.record("Expected .thinking chunk")
        }
    }

    @Test("Extracts both thinking and content from same event")
    func extractBothThinkingAndContent() {
        let json = #"{"choices":[{"delta":{"thinking":"Reason","content":"Output"},"index":0}]}"#
        let chunks = processor.processSSEEvent(json)
        #expect(chunks.count == 2)
        let hasThinking = chunks.contains { if case .thinking = $0 { return true } else { return false } }
        let hasContent = chunks.contains { if case .content = $0 { return true } else { return false } }
        #expect(hasThinking)
        #expect(hasContent)
    }

    // MARK: - finish_reason extraction

    @Test("Extracts finish_reason from SSE event")
    func extractFinishReason() {
        let json = #"{"choices":[{"delta":{},"finish_reason":"stop","index":0}]}"#
        let chunks = processor.processSSEEvent(json)
        #expect(chunks.count == 1)
        if case .finishReason(let reason) = chunks.first {
            #expect(reason == "stop")
        } else {
            Issue.record("Expected .finishReason chunk")
        }
    }

    @Test("Extracts finish_reason 'length' for truncation detection")
    func extractFinishReasonLength() {
        let json = #"{"choices":[{"delta":{"content":"..."},"finish_reason":"length","index":0}]}"#
        let chunks = processor.processSSEEvent(json)
        let hasLength = chunks.contains {
            if case .finishReason(let r) = $0 { return r == "length" } else { return false }
        }
        #expect(hasLength)
    }

    @Test("Returns both finish_reason and content in same event")
    func finishReasonWithContent() {
        let json = #"{"choices":[{"delta":{"content":"end"},"finish_reason":"stop","index":0}]}"#
        let chunks = processor.processSSEEvent(json)
        let hasContent = chunks.contains { if case .content = $0 { return true } else { return false } }
        let hasFinish = chunks.contains { if case .finishReason = $0 { return true } else { return false } }
        #expect(hasContent)
        #expect(hasFinish)
    }

    // MARK: - Malformed input handling

    @Test("Returns empty array for invalid JSON")
    func invalidJSON() {
        let chunks = processor.processSSEEvent("not json at all")
        #expect(chunks.isEmpty)
    }

    @Test("Returns empty array for JSON without choices")
    func missingChoices() {
        let chunks = processor.processSSEEvent(#"{"data":"something"}"#)
        #expect(chunks.isEmpty)
    }

    @Test("Returns empty array for empty choices array")
    func emptyChoices() {
        let chunks = processor.processSSEEvent(#"{"choices":[]}"#)
        #expect(chunks.isEmpty)
    }

    @Test("Returns empty array for missing delta")
    func missingDelta() {
        let json = #"{"choices":[{"index":0}]}"#
        let chunks = processor.processSSEEvent(json)
        #expect(chunks.isEmpty)
    }

    @Test("Ignores empty content strings")
    func emptyContent() {
        let json = #"{"choices":[{"delta":{"content":""},"index":0}]}"#
        let chunks = processor.processSSEEvent(json)
        #expect(chunks.isEmpty)
    }

    @Test("Ignores empty thinking strings")
    func emptyThinking() {
        let json = #"{"choices":[{"delta":{"thinking":""},"index":0}]}"#
        let chunks = processor.processSSEEvent(json)
        #expect(chunks.isEmpty)
    }

    @Test("Returns empty for completely empty string")
    func emptyString() {
        let chunks = processor.processSSEEvent("")
        #expect(chunks.isEmpty)
    }

    // MARK: - finish_reason without delta

    @Test("Extracts finish_reason even when delta is missing")
    func finishReasonNoDelta() {
        let json = #"{"choices":[{"finish_reason":"stop","index":0}]}"#
        let chunks = processor.processSSEEvent(json)
        #expect(chunks.count == 1)
        if case .finishReason(let reason) = chunks.first {
            #expect(reason == "stop")
        } else {
            Issue.record("Expected .finishReason chunk")
        }
    }
}
