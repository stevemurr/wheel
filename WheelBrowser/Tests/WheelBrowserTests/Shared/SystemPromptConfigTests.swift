import Foundation
import Testing
@testable import WheelBrowser

@MainActor
@Suite("System Prompt Config", .serialized)
struct SystemPromptConfigTests {
    @Test("Default chat prompt biases toward detail without manual follow-up formatting")
    func defaultChatPromptBiasesTowardDetail() {
        let prompt = SystemPromptConfig.defaultChatPrompt

        #expect(prompt.contains("Default to sufficiently detailed answers for non-trivial questions."))
        #expect(prompt.contains("When the user explicitly asks for depth, detail, step-by-step explanation, or thoroughness, provide it."))
        #expect(prompt.contains("Avoid terse summaries unless the user asks for brevity or the question is simple."))
        #expect(prompt.localizedCaseInsensitiveContains("Follow-up questions") == false)
    }

    @Test("Custom chat prompt fully overrides the default prompt")
    func customChatPromptOverridesDefault() {
        let settings = AppSettings.shared
        let originalPrompt = settings.chatSystemPrompt
        defer {
            settings.chatSystemPrompt = originalPrompt
        }

        settings.chatSystemPrompt = ""
        #expect(SystemPromptConfig.chatPrompt == SystemPromptConfig.defaultChatPrompt)

        settings.chatSystemPrompt = "Reply with maximal detail."
        #expect(SystemPromptConfig.chatPrompt == "Reply with maximal detail.")
    }
}
