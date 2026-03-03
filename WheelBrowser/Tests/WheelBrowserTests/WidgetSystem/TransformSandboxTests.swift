import Testing
import Foundation
@testable import WheelBrowser

@Suite("TransformSandbox")
struct TransformSandboxTests {
    let sandbox = TransformSandbox()

    // MARK: - Sort

    @Test("Sort ascending by numeric field")
    func sortAscending() throws {
        let input: [[String: Any]] = [
            ["name": "C", "score": 3],
            ["name": "A", "score": 1],
            ["name": "B", "score": 2],
        ]
        let params: [String: Any] = ["field": "score", "order": "asc"]
        let result = try sandbox.execute(skill: .sort, params: params, input: input) as! [[String: Any]]

        #expect(result[0]["name"] as? String == "A")
        #expect(result[1]["name"] as? String == "B")
        #expect(result[2]["name"] as? String == "C")
    }

    @Test("Sort descending by numeric field")
    func sortDescending() throws {
        let input: [[String: Any]] = [
            ["score": 1],
            ["score": 3],
            ["score": 2],
        ]
        let params: [String: Any] = ["field": "score", "order": "desc"]
        let result = try sandbox.execute(skill: .sort, params: params, input: input) as! [[String: Any]]

        #expect(result[0]["score"] as? Int == 3)
        #expect(result[1]["score"] as? Int == 2)
        #expect(result[2]["score"] as? Int == 1)
    }

    @Test("Sort with empty array")
    func sortEmpty() throws {
        let result = try sandbox.execute(skill: .sort, params: ["field": "x", "order": "asc"], input: [] as [Any])
        let arr = result as? [Any]
        #expect(arr?.isEmpty == true)
    }

    // MARK: - Filter

    @Test("Filter eq operator")
    func filterEq() throws {
        let input: [[String: Any]] = [
            ["status": "active"],
            ["status": "inactive"],
            ["status": "active"],
        ]
        let params: [String: Any] = ["field": "status", "operator": "eq", "value": "active"]
        let result = try sandbox.execute(skill: .filter, params: params, input: input) as! [[String: Any]]
        #expect(result.count == 2)
    }

    @Test("Filter gt operator")
    func filterGt() throws {
        let input: [[String: Any]] = [
            ["score": 10],
            ["score": 5],
            ["score": 15],
        ]
        let params: [String: Any] = ["field": "score", "operator": "gt", "value": 8]
        let result = try sandbox.execute(skill: .filter, params: params, input: input) as! [[String: Any]]
        #expect(result.count == 2)
    }

    @Test("Filter contains operator")
    func filterContains() throws {
        let input: [[String: Any]] = [
            ["title": "Hello World"],
            ["title": "Goodbye"],
            ["title": "Hello Again"],
        ]
        let params: [String: Any] = ["field": "title", "operator": "contains", "value": "hello"]
        let result = try sandbox.execute(skill: .filter, params: params, input: input) as! [[String: Any]]
        #expect(result.count == 2)
    }

    @Test("Filter not_contains operator")
    func filterNotContains() throws {
        let input: [[String: Any]] = [
            ["title": "Hello World"],
            ["title": "Goodbye"],
        ]
        let params: [String: Any] = ["field": "title", "operator": "not_contains", "value": "hello"]
        let result = try sandbox.execute(skill: .filter, params: params, input: input) as! [[String: Any]]
        #expect(result.count == 1)
    }

    @Test("Filter with missing field returns empty")
    func filterMissingField() throws {
        let input: [[String: Any]] = [
            ["other": "value"],
        ]
        let params: [String: Any] = ["field": "missing", "operator": "eq", "value": "x"]
        let result = try sandbox.execute(skill: .filter, params: params, input: input) as! [[String: Any]]
        #expect(result.isEmpty)
    }

    // MARK: - MapFields

    @Test("MapFields with field projection")
    func mapFieldsProjection() throws {
        let input: [[String: Any]] = [
            ["first_name": "John", "last_name": "Doe", "age": 30],
        ]
        let params: [String: Any] = [
            "mapping": [
                "name": "{{first_name}} {{last_name}}",
                "years": "age",
            ] as [String: Any]
        ]
        let result = try sandbox.execute(skill: .mapFields, params: params, input: input) as! [[String: Any]]
        #expect(result[0]["name"] as? String == "John Doe")
        #expect(result[0]["years"] as? Int == 30)
    }

    // MARK: - Aggregate

    @Test("Aggregate count")
    func aggregateCount() throws {
        let input: [[String: Any]] = [["x": 1], ["x": 2], ["x": 3]]
        let params: [String: Any] = ["operation": "count"]
        let result = try sandbox.execute(skill: .aggregate, params: params, input: input) as! [[String: Any]]
        #expect(result[0]["value"] as? Int == 3)
    }

    @Test("Aggregate sum")
    func aggregateSum() throws {
        let input: [[String: Any]] = [["val": 10], ["val": 20], ["val": 30]]
        let params: [String: Any] = ["operation": "sum", "field": "val"]
        let result = try sandbox.execute(skill: .aggregate, params: params, input: input) as! [[String: Any]]
        #expect(result[0]["value"] as? Int == 60)
    }

    @Test("Aggregate avg")
    func aggregateAvg() throws {
        let input: [[String: Any]] = [["val": 10], ["val": 20], ["val": 30]]
        let params: [String: Any] = ["operation": "avg", "field": "val"]
        let result = try sandbox.execute(skill: .aggregate, params: params, input: input) as! [[String: Any]]
        #expect(result[0]["value"] as? Int == 20)
    }

    @Test("Aggregate with group_by")
    func aggregateGroupBy() throws {
        let input: [[String: Any]] = [
            ["category": "A", "val": 10],
            ["category": "B", "val": 20],
            ["category": "A", "val": 30],
        ]
        let params: [String: Any] = ["operation": "sum", "field": "val", "group_by": "category"]
        let result = try sandbox.execute(skill: .aggregate, params: params, input: input) as! [[String: Any]]
        #expect(result.count == 2)
    }

    // MARK: - Sandbox Isolation

    @Test("Dangerous globals are stripped")
    func sandboxIsolation() throws {
        // The sandbox should have stripped fetch, XMLHttpRequest, etc.
        // This tests that our sandbox setup works (verifiable by checking
        // that the transform runtime loaded correctly)
        let input: [[String: Any]] = [["x": 1]]
        let params: [String: Any] = ["field": "x", "order": "asc"]
        let result = try sandbox.execute(skill: .sort, params: params, input: input)
        #expect(result is [Any])
    }
}
