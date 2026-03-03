import Testing
import Foundation
@testable import WheelBrowser

@Suite("RenderTableSkill")
struct RenderTableSkillTests {
    let skill = RenderTableSkill()

    @Test("Basic columns extraction")
    func basicColumns() async throws {
        let result = try await skill.execute(params: [
            "columns": [
                ["key": "name", "label": "Name"],
                ["key": "age", "label": "Age"],
            ] as [[String: Any]],
            "input": [["name": "Alice", "age": 30]] as [[String: Any]],
        ])
        guard case .table(let columns, let rows) = result as? RenderInput else {
            Issue.record("Expected table RenderInput")
            return
        }
        #expect(columns.count == 2)
        #expect(columns[0].key == "name")
        #expect(columns[0].label == "Name")
        #expect(columns[1].key == "age")
        #expect(rows.count == 1)
    }

    @Test("Missing params error")
    func missingParams() async {
        do {
            _ = try await skill.execute(params: [
                "input": [] as [[String: Any]],
            ])
            Issue.record("Expected error for missing columns")
        } catch {
            // Expected: columns param is required
        }
    }

    @Test("Default format values")
    func defaultFormatValues() async throws {
        let result = try await skill.execute(params: [
            "columns": [
                ["key": "val", "label": "Value"],
            ] as [[String: Any]],
            "input": [] as [[String: Any]],
        ])
        guard case .table(let columns, _) = result as? RenderInput else {
            Issue.record("Expected table RenderInput")
            return
        }
        #expect(columns[0].format == .plain)
    }

    @Test("Sortable column defaults")
    func sortableDefaults() async throws {
        let result = try await skill.execute(params: [
            "columns": [
                ["key": "x", "label": "X"],
                ["key": "y", "label": "Y", "sortable": false],
            ] as [[String: Any]],
            "input": [] as [[String: Any]],
        ])
        guard case .table(let columns, _) = result as? RenderInput else {
            Issue.record("Expected table RenderInput")
            return
        }
        #expect(columns[0].sortable == true)
        #expect(columns[1].sortable == false)
    }

    @Test("Empty rows")
    func emptyRows() async throws {
        let result = try await skill.execute(params: [
            "columns": [
                ["key": "id", "label": "ID"],
            ] as [[String: Any]],
            "input": [] as [[String: Any]],
        ])
        guard case .table(_, let rows) = result as? RenderInput else {
            Issue.record("Expected table RenderInput")
            return
        }
        #expect(rows.isEmpty)
    }
}
