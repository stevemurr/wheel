import Testing
import Foundation
@testable import WheelBrowser

@Suite("RenderChartSkill")
struct RenderChartSkillTests {
    let skill = RenderChartSkill()

    private func executeChart(_ params: [String: Any]) async throws -> ChartConfig {
        let result = try await skill.execute(params: params)
        guard case .chart(let config) = result as? RenderInput else {
            Issue.record("Expected chart RenderInput")
            throw WidgetError.renderFailed("Not a chart")
        }
        return config
    }

    @Test("Line chart type")
    func lineChartType() async throws {
        let config = try await executeChart([
            "chart_type": "line",
            "x_field": "date",
            "y_field": "price",
            "input": [["date": "2026-01-01", "price": 100]] as [[String: Any]],
        ])
        #expect(config.type == .line)
    }

    @Test("Bar chart type")
    func barChartType() async throws {
        let config = try await executeChart([
            "chart_type": "bar",
            "x_field": "category",
            "y_field": "count",
            "input": [["category": "A", "count": 10]] as [[String: Any]],
        ])
        #expect(config.type == .bar)
    }

    @Test("Default chart type when missing")
    func defaultChartType() async throws {
        let config = try await executeChart([
            "x_field": "x",
            "y_field": "y",
            "input": [] as [[String: Any]],
        ])
        #expect(config.type == .line)
    }

    @Test("Pie/doughnut chart type")
    func pieChartType() async throws {
        let config = try await executeChart([
            "chart_type": "pie",
            "x_field": "label",
            "y_field": "value",
            "input": [["label": "A", "value": 30]] as [[String: Any]],
        ])
        #expect(config.type == .pie)

        let doughnutConfig = try await executeChart([
            "chart_type": "doughnut",
            "x_field": "label",
            "y_field": "value",
            "input": [["label": "B", "value": 70]] as [[String: Any]],
        ])
        #expect(doughnutConfig.type == .doughnut)
    }

    @Test("Chart with optional fields")
    func chartWithOptionalFields() async throws {
        let config = try await executeChart([
            "chart_type": "area",
            "title": "Revenue Over Time",
            "x_field": "month",
            "y_field": "revenue",
            "series_field": "region",
            "color_scheme": "blue",
            "input": [["month": "Jan", "revenue": 100, "region": "US"]] as [[String: Any]],
        ])
        #expect(config.type == .area)
        #expect(config.title == "Revenue Over Time")
        #expect(config.seriesField == "region")
        #expect(config.colorScheme == "blue")
        #expect(config.xField == "month")
        #expect(config.yField == "revenue")
    }
}
