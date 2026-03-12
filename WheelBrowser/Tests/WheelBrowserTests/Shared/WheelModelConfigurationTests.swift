import LanguageModelContextManagement
import Testing
@testable import WheelBrowser

@Suite("WheelModelConfiguration")
struct WheelModelConfigurationTests {
    @Test("Apple provider uses a larger default response reserve")
    func appleProviderDefaultBudgetPolicy() {
        #expect(
            WheelModelProviderID.apple.defaultBudgetPolicy
                == BudgetPolicy(reservedOutputTokens: 1024, defaultContextWindowTokens: 8192)
        )
    }

    @Test("Remote providers assume larger default windows and response reserves")
    func remoteProviderDefaultBudgetPolicy() {
        let expected = BudgetPolicy(
            reservedOutputTokens: 1536,
            defaultContextWindowTokens: 16384
        )

        #expect(WheelModelProviderID.openAI.defaultBudgetPolicy == expected)
        #expect(WheelModelProviderID.vllm.defaultBudgetPolicy == expected)
    }
}
