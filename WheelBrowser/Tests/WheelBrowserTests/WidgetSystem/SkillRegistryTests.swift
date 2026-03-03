import Testing
import Foundation
@testable import WheelBrowser

@Suite("SkillRegistry")
struct SkillRegistryTests {

    @Test("Default registry has all 13 skills")
    func defaultRegistryComplete() {
        let registry = SkillRegistry.createDefault()
        let prompt = registry.systemPromptRegistry()
        for skill in SkillName.allCases {
            #expect(prompt.contains(skill.rawValue), "Missing skill: \(skill.rawValue)")
        }
    }

    @Test("Unknown skill throws error")
    func unknownSkill() async {
        // Register only one skill
        let registry = SkillRegistry(skills: [RenderListSkill()])
        do {
            _ = try await registry.execute(skill: .fetchRedditPosts, params: [:])
            Issue.record("Expected unknownSkill error")
        } catch let error as WidgetError {
            if case .unknownSkill(let name) = error {
                #expect(name == "fetch_reddit_posts")
            } else {
                Issue.record("Wrong error type: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("System prompt registry contains skill schemas")
    func systemPromptContent() {
        let registry = SkillRegistry.createDefault()
        let prompt = registry.systemPromptRegistry()
        #expect(prompt.contains("Available skills:"))
        #expect(prompt.contains("fetch_reddit_posts"))
        #expect(prompt.contains("render_list"))
        #expect(prompt.contains("subreddit"))
    }
}
