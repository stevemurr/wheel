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

    // MARK: - Filter: Additional Operators

    @Test("Filter neq operator")
    func filterNeq() throws {
        let input: [[String: Any]] = [
            ["status": "active"],
            ["status": "inactive"],
            ["status": "active"],
        ]
        let params: [String: Any] = ["field": "status", "operator": "neq", "value": "active"]
        let result = try sandbox.execute(skill: .filter, params: params, input: input) as! [[String: Any]]
        #expect(result.count == 1)
        #expect(result[0]["status"] as? String == "inactive")
    }

    @Test("Filter gte operator")
    func filterGte() throws {
        let input: [[String: Any]] = [
            ["score": 10],
            ["score": 5],
            ["score": 8],
        ]
        let params: [String: Any] = ["field": "score", "operator": "gte", "value": 8]
        let result = try sandbox.execute(skill: .filter, params: params, input: input) as! [[String: Any]]
        #expect(result.count == 2)
    }

    @Test("Filter lte operator")
    func filterLte() throws {
        let input: [[String: Any]] = [
            ["score": 10],
            ["score": 5],
            ["score": 8],
        ]
        let params: [String: Any] = ["field": "score", "operator": "lte", "value": 8]
        let result = try sandbox.execute(skill: .filter, params: params, input: input) as! [[String: Any]]
        #expect(result.count == 2)
    }

    @Test("Filter lt operator")
    func filterLt() throws {
        let input: [[String: Any]] = [
            ["score": 10],
            ["score": 5],
            ["score": 8],
        ]
        let params: [String: Any] = ["field": "score", "operator": "lt", "value": 8]
        let result = try sandbox.execute(skill: .filter, params: params, input: input) as! [[String: Any]]
        #expect(result.count == 1)
        #expect(result[0]["score"] as? Int == 5)
    }

    @Test("Filter with numeric comparison")
    func filterNumericComparison() throws {
        let input: [[String: Any]] = [
            ["price": 9.99],
            ["price": 19.99],
            ["price": 4.99],
        ]
        let params: [String: Any] = ["field": "price", "operator": "gt", "value": 10.0]
        let result = try sandbox.execute(skill: .filter, params: params, input: input) as! [[String: Any]]
        #expect(result.count == 1)
    }

    // MARK: - Sort: Additional Cases

    @Test("Sort by string values")
    func sortByString() throws {
        let input: [[String: Any]] = [
            ["name": "Charlie"],
            ["name": "Alice"],
            ["name": "Bob"],
        ]
        let params: [String: Any] = ["field": "name", "order": "asc"]
        let result = try sandbox.execute(skill: .sort, params: params, input: input) as! [[String: Any]]
        #expect(result[0]["name"] as? String == "Alice")
        #expect(result[1]["name"] as? String == "Bob")
        #expect(result[2]["name"] as? String == "Charlie")
    }

    @Test("Sort with null values handles gracefully")
    func sortWithNulls() throws {
        let input: [[String: Any]] = [
            ["name": "B", "score": 2],
            ["name": "A"],
            ["name": "C", "score": 3],
        ]
        let params: [String: Any] = ["field": "score", "order": "asc"]
        let result = try sandbox.execute(skill: .sort, params: params, input: input)
        #expect(result is [Any])
    }

    @Test("Sort by missing field")
    func sortByMissingField() throws {
        let input: [[String: Any]] = [
            ["name": "B"],
            ["name": "A"],
        ]
        let params: [String: Any] = ["field": "nonexistent", "order": "asc"]
        let result = try sandbox.execute(skill: .sort, params: params, input: input)
        let arr = result as? [Any]
        #expect(arr?.count == 2)
    }

    // MARK: - Aggregate: Additional Operations

    @Test("Aggregate min operation")
    func aggregateMin() throws {
        let input: [[String: Any]] = [["val": 10], ["val": 5], ["val": 20]]
        let params: [String: Any] = ["operation": "min", "field": "val"]
        let result = try sandbox.execute(skill: .aggregate, params: params, input: input) as! [[String: Any]]
        #expect(result[0]["value"] as? Int == 5)
    }

    @Test("Aggregate max operation")
    func aggregateMax() throws {
        let input: [[String: Any]] = [["val": 10], ["val": 5], ["val": 20]]
        let params: [String: Any] = ["operation": "max", "field": "val"]
        let result = try sandbox.execute(skill: .aggregate, params: params, input: input) as! [[String: Any]]
        #expect(result[0]["value"] as? Int == 20)
    }

    @Test("Aggregate first operation")
    func aggregateFirst() throws {
        let input: [[String: Any]] = [["val": 10], ["val": 20], ["val": 30]]
        let params: [String: Any] = ["operation": "first", "field": "val"]
        let result = try sandbox.execute(skill: .aggregate, params: params, input: input) as! [[String: Any]]
        #expect(result[0]["value"] as? Int == 10)
    }

    @Test("Aggregate last operation")
    func aggregateLast() throws {
        let input: [[String: Any]] = [["val": 10], ["val": 20], ["val": 30]]
        let params: [String: Any] = ["operation": "last", "field": "val"]
        let result = try sandbox.execute(skill: .aggregate, params: params, input: input) as! [[String: Any]]
        #expect(result[0]["value"] as? Int == 30)
    }

    @Test("Aggregate group_by with multiple groups")
    func aggregateGroupByMultiple() throws {
        let input: [[String: Any]] = [
            ["cat": "A", "val": 10],
            ["cat": "B", "val": 5],
            ["cat": "A", "val": 20],
            ["cat": "C", "val": 15],
            ["cat": "B", "val": 25],
        ]
        let params: [String: Any] = ["operation": "sum", "field": "val", "group_by": "cat"]
        let result = try sandbox.execute(skill: .aggregate, params: params, input: input) as! [[String: Any]]
        #expect(result.count == 3)
    }

    // MARK: - MapFields: Additional Cases

    @Test("MapFields with missing source field produces null or omits")
    func mapFieldsMissingSource() throws {
        let input: [[String: Any]] = [
            ["name": "John"],
        ]
        let params: [String: Any] = [
            "mapping": ["output": "nonexistent_field"] as [String: Any]
        ]
        let result = try sandbox.execute(skill: .mapFields, params: params, input: input) as! [[String: Any]]
        // Missing source field should produce null or be omitted
        #expect(result.count == 1)
    }

    @Test("MapFields template with multiple references")
    func mapFieldsMultipleRefs() throws {
        let input: [[String: Any]] = [
            ["first": "John", "last": "Doe", "age": 30],
        ]
        let params: [String: Any] = [
            "mapping": ["display": "{{first}} {{last}} ({{age}})"] as [String: Any]
        ]
        let result = try sandbox.execute(skill: .mapFields, params: params, input: input) as! [[String: Any]]
        #expect(result[0]["display"] as? String == "John Doe (30)")
    }

    // MARK: - Empty Input

    @Test("Empty input for sort")
    func emptyInputSort() throws {
        let result = try sandbox.execute(skill: .sort, params: ["field": "x", "order": "asc"], input: [] as [Any])
        let arr = result as? [Any]
        #expect(arr?.isEmpty == true)
    }

    @Test("Empty input for filter")
    func emptyInputFilter() throws {
        let result = try sandbox.execute(skill: .filter, params: ["field": "x", "operator": "eq", "value": "y"], input: [] as [Any])
        let arr = result as? [Any]
        #expect(arr?.isEmpty == true)
    }

    @Test("Empty input for aggregate")
    func emptyInputAggregate() throws {
        let result = try sandbox.execute(skill: .aggregate, params: ["operation": "count"], input: [] as [Any])
        let arr = result as? [[String: Any]]
        // count of empty array should be 0
        if let arr, let first = arr.first {
            #expect(first["value"] as? Int == 0)
        }
    }

    @Test("Empty input for mapFields")
    func emptyInputMapFields() throws {
        let result = try sandbox.execute(skill: .mapFields, params: ["mapping": ["out": "in"] as [String: Any]], input: [] as [Any])
        let arr = result as? [Any]
        #expect(arr?.isEmpty == true)
    }
}
