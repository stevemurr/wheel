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
}
