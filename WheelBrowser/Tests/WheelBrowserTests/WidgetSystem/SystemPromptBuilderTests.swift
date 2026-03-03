import Testing
import Foundation
@testable import WheelBrowser

@Suite("SystemPromptBuilder")
struct SystemPromptBuilderTests {

    @Test("Output contains preamble text")
    func containsPreamble() {
        let registry = SkillRegistry.createDefault()
        let prompt = SystemPromptBuilder.build(registry: registry)
        #expect(prompt.contains("widget pipeline designer"))
    }

    @Test("Output contains skill names from registry")
    func containsSkillNames() {
        let registry = SkillRegistry.createDefault()
        let prompt = SystemPromptBuilder.build(registry: registry)
        #expect(prompt.contains("fetch_reddit_posts"))
        #expect(prompt.contains("render_list"))
        #expect(prompt.contains("sort"))
        #expect(prompt.contains("render_chart"))
    }

    @Test("Output contains schema section")
    func containsSchemaSection() {
        let registry = SkillRegistry.createDefault()
        let prompt = SystemPromptBuilder.build(registry: registry)
        #expect(prompt.contains("Output Schema"))
        #expect(prompt.contains("refresh_interval_seconds"))
    }
}
