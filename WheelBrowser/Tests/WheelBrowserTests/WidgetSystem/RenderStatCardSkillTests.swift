import Testing
import Foundation
@testable import WheelBrowser

@Suite("RenderStatCardSkill")
struct RenderStatCardSkillTests {
    let skill = RenderStatCardSkill()

    private func executeStatCard(_ params: [String: Any]) async throws -> (label: String, value: String, format: ValueFormat, delta: Delta?) {
        let result = try await skill.execute(params: params)
        guard case .statCard(let label, let value, let format, let delta) = result as? RenderInput else {
            Issue.record("Expected statCard RenderInput")
            throw WidgetError.renderFailed("Not a statCard")
        }
        return (label, value, format, delta)
    }

    @Test("Currency formatting")
    func currencyFormatting() async throws {
        let card = try await executeStatCard([
            "label": "Price",
            "value_field": "price",
            "format": "currency",
            "input": [["price": 29.99]] as [[String: Any]],
        ])
        #expect(card.value == "$29.99")
        #expect(card.format == .currency)
    }

    @Test("Percentage formatting")
    func percentFormatting() async throws {
        let card = try await executeStatCard([
            "label": "Growth",
            "value_field": "rate",
            "format": "percent",
            "input": [["rate": 12.5]] as [[String: Any]],
        ])
        #expect(card.value == "12.5%")
        #expect(card.format == .percent)
    }

    @Test("Plain number formatting")
    func plainFormatting() async throws {
        let card = try await executeStatCard([
            "label": "Count",
            "value_field": "n",
            "format": "plain",
            "input": [["n": 42]] as [[String: Any]],
        ])
        #expect(card.value == "42")
        #expect(card.format == .plain)
    }

    @Test("Temperature formatting")
    func temperatureFormatting() async throws {
        let card = try await executeStatCard([
            "label": "Temp",
            "value_field": "temp",
            "format": "temperature",
            "input": [["temp": 72.0]] as [[String: Any]],
        ])
        #expect(card.value.contains("72"))
        #expect(card.format == .temperature)
    }

    @Test("K suffix for thousands")
    func kSuffix() async throws {
        let card = try await executeStatCard([
            "label": "Users",
            "value_field": "count",
            "format": "number",
            "input": [["count": 5000.0]] as [[String: Any]],
        ])
        #expect(card.value == "5.0K")
    }

    @Test("M suffix for millions")
    func mSuffix() async throws {
        let card = try await executeStatCard([
            "label": "Revenue",
            "value_field": "amount",
            "format": "number",
            "input": [["amount": 2500000.0]] as [[String: Any]],
        ])
        #expect(card.value == "2.5M")
    }

    @Test("B suffix for billions")
    func bSuffix() async throws {
        let card = try await executeStatCard([
            "label": "Market Cap",
            "value_field": "cap",
            "format": "number",
            "input": [["cap": 1200000000.0]] as [[String: Any]],
        ])
        #expect(card.value == "1.2B")
    }

    @Test("Delta positive color")
    func deltaPositive() async throws {
        let card = try await executeStatCard([
            "label": "Price",
            "value_field": "price",
            "delta_field": "change",
            "delta_label": "vs yesterday",
            "input": [["price": 100, "change": 5.5]] as [[String: Any]],
        ])
        #expect(card.delta != nil)
        #expect(card.delta!.value == 5.5)
        #expect(card.delta!.label == "vs yesterday")
    }

    @Test("Delta negative color")
    func deltaNegative() async throws {
        let card = try await executeStatCard([
            "label": "Price",
            "value_field": "price",
            "delta_field": "change",
            "input": [["price": 90, "change": -3.2]] as [[String: Any]],
        ])
        #expect(card.delta != nil)
        #expect(card.delta!.value == -3.2)
    }

    @Test("Missing optional fields")
    func missingOptionalFields() async throws {
        let card = try await executeStatCard([
            "label": "Value",
            "value_field": "val",
            "input": [["val": "N/A"]] as [[String: Any]],
        ])
        #expect(card.delta == nil)
        #expect(card.format == .plain)
    }
}
