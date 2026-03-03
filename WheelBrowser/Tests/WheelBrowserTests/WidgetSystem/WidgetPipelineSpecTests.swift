import Testing
import Foundation
@testable import WheelBrowser

@Suite("WidgetPipelineSpec Codable")
struct WidgetPipelineSpecTests {

    @Test("Encode and decode round-trip")
    func roundTrip() throws {
        let spec = WidgetPipelineSpec(
            title: "Test Widget",
            refreshIntervalSeconds: 600,
            pipeline: [
                PipelineStep(
                    id: "fetch",
                    skill: .fetchRedditPosts,
                    params: [
                        "subreddit": AnyCodable("swift"),
                        "sort": AnyCodable("hot"),
                        "limit": AnyCodable(10),
                    ]
                ),
                PipelineStep(
                    id: "render",
                    skill: .renderList,
                    params: [
                        "input": AnyCodable("{{fetch.output}}"),
                        "headline_field": AnyCodable("title"),
                    ]
                ),
            ]
        )

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(WidgetPipelineSpec.self, from: data)

        #expect(decoded.title == "Test Widget")
        #expect(decoded.refreshIntervalSeconds == 600)
        #expect(decoded.pipeline.count == 2)
        #expect(decoded.pipeline[0].id == "fetch")
        #expect(decoded.pipeline[0].skill == .fetchRedditPosts)
        #expect(decoded.pipeline[1].skill == .renderList)
    }

    @Test("Decode from JSON string")
    func decodeFromJSON() throws {
        let json = """
        {
            "title": "BTC Price",
            "refresh_interval_seconds": 900,
            "pipeline": [
                {
                    "id": "prices",
                    "skill": "fetch_crypto_price",
                    "params": {"coin_id": "bitcoin", "days": 7}
                },
                {
                    "id": "render",
                    "skill": "render_chart",
                    "params": {"input": "{{prices.output}}", "chart_type": "line", "x_field": "timestamp_ms", "y_field": "price"}
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let spec = try JSONDecoder().decode(WidgetPipelineSpec.self, from: data)

        #expect(spec.title == "BTC Price")
        #expect(spec.refreshIntervalSeconds == 900)
        #expect(spec.pipeline[0].skill == .fetchCryptoPrice)
        #expect(spec.pipeline[1].skill == .renderChart)
    }

    // MARK: - Additional Codable Tests

    @Test("Snake_case field names decode correctly")
    func snakeCaseDecoding() throws {
        let json = """
        {
            "title": "Test",
            "refresh_interval_seconds": 300,
            "pipeline": [
                {"id": "render", "skill": "render_stat_card", "params": {"value_field": "val"}}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let spec = try JSONDecoder().decode(WidgetPipelineSpec.self, from: data)
        #expect(spec.refreshIntervalSeconds == 300)
        #expect(spec.pipeline[0].skill == .renderStatCard)
    }

    @Test("Missing optional fields get defaults")
    func missingOptionalFields() throws {
        let json = """
        {
            "title": "Minimal",
            "refresh_interval_seconds": 600,
            "pipeline": []
        }
        """
        let data = json.data(using: .utf8)!
        let spec = try JSONDecoder().decode(WidgetPipelineSpec.self, from: data)
        #expect(spec.thinking == nil)
        #expect(spec.widgetId != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
    }

    @Test("Invalid skill name in JSON throws DecodingError")
    func invalidSkillName() {
        let json = """
        {
            "title": "Bad",
            "refresh_interval_seconds": 300,
            "pipeline": [
                {"id": "step", "skill": "nonexistent_skill", "params": {}}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(WidgetPipelineSpec.self, from: data)
        }
    }

    @Test("PipelineStep encode/decode round-trip")
    func stepRoundTrip() throws {
        let step = PipelineStep(
            id: "test_step",
            skill: .filter,
            params: [
                "field": AnyCodable("status"),
                "operator": AnyCodable("eq"),
                "value": AnyCodable("active"),
            ]
        )
        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(PipelineStep.self, from: data)
        #expect(decoded.id == "test_step")
        #expect(decoded.skill == .filter)
        #expect(decoded.params["field"]?.stringValue == "status")
        #expect(decoded.params["operator"]?.stringValue == "eq")
    }

    @Test("Empty pipeline array decodes")
    func emptyPipelineDecodes() throws {
        let json = """
        {
            "title": "Empty",
            "refresh_interval_seconds": 300,
            "pipeline": []
        }
        """
        let data = json.data(using: .utf8)!
        let spec = try JSONDecoder().decode(WidgetPipelineSpec.self, from: data)
        #expect(spec.pipeline.isEmpty)
    }

    @Test("Title field presence")
    func titleFieldPresence() throws {
        let spec = WidgetPipelineSpec(
            title: "My Widget Title",
            refreshIntervalSeconds: 600,
            pipeline: []
        )
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(WidgetPipelineSpec.self, from: data)
        #expect(decoded.title == "My Widget Title")
    }
}
