import Testing
import Foundation
@testable import WheelBrowser

@Suite("RenderCompositeSkill")
struct RenderCompositeSkillTests {
    let skill = RenderCompositeSkill()

    @Test("VStack layout")
    func vstackLayout() async throws {
        let result = try await skill.execute(params: [
            "layout": "vstack",
            "input": [["title": "Item"]] as [[String: Any]],
            "children": [
                ["skill": "render_list", "params": ["headline_field": "title"]] as [String: Any],
            ] as [[String: Any]],
        ])
        guard case .composite(let layout, let children) = result as? RenderInput else {
            Issue.record("Expected composite RenderInput")
            return
        }
        #expect(layout == .vstack)
        #expect(children.count == 1)
    }

    @Test("HStack layout")
    func hstackLayout() async throws {
        let result = try await skill.execute(params: [
            "layout": "hstack",
            "input": [["title": "Item"]] as [[String: Any]],
            "children": [
                ["skill": "render_list", "params": ["headline_field": "title"]] as [String: Any],
            ] as [[String: Any]],
        ])
        guard case .composite(let layout, _) = result as? RenderInput else {
            Issue.record("Expected composite RenderInput")
            return
        }
        #expect(layout == .hstack)
    }

    @Test("Grid layout")
    func gridLayout() async throws {
        let result = try await skill.execute(params: [
            "layout": "grid_2col",
            "input": [["title": "Item"]] as [[String: Any]],
            "children": [
                ["skill": "render_list", "params": ["headline_field": "title"]] as [String: Any],
            ] as [[String: Any]],
        ])
        guard case .composite(let layout, _) = result as? RenderInput else {
            Issue.record("Expected composite RenderInput")
            return
        }
        #expect(layout == .grid2col)
    }

    @Test("Default layout when not specified")
    func defaultLayout() async throws {
        let result = try await skill.execute(params: [
            "input": [["title": "Item"]] as [[String: Any]],
            "children": [
                ["skill": "render_list", "params": ["headline_field": "title"]] as [String: Any],
            ] as [[String: Any]],
        ])
        guard case .composite(let layout, _) = result as? RenderInput else {
            Issue.record("Expected composite RenderInput")
            return
        }
        #expect(layout == .vstack)
    }

    @Test("Parent input injection to children")
    func parentInputInjection() async throws {
        let input = [["title": "Injected"]] as [[String: Any]]
        let result = try await skill.execute(params: [
            "layout": "vstack",
            "input": input,
            "children": [
                ["skill": "render_list", "params": ["headline_field": "title"]] as [String: Any],
            ] as [[String: Any]],
        ])
        guard case .composite(_, let children) = result as? RenderInput else {
            Issue.record("Expected composite RenderInput")
            return
        }
        #expect(children.count == 1)
        if case .list(_, let items) = children[0] {
            #expect(items[0].headline == "Injected")
        } else {
            Issue.record("Expected list child")
        }
    }

    @Test("Missing children param throws error")
    func missingChildren() async throws {
        await #expect(throws: WidgetError.self) {
            _ = try await skill.execute(params: [
                "layout": "vstack",
                "input": [["title": "Item"]] as [[String: Any]],
            ])
        }
    }
}
