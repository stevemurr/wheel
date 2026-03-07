import Foundation
import FoundationModels

protocol WidgetManifestGenerator: Sendable {
    func generate(prompt: String) async throws -> WidgetManifest
}

@Generable(description: "A complete widget manifest for the Wheel dashboard.")
struct GeneratedWidgetManifest: Sendable {
    let id: String?
    let version: String
    let widgetType: String
    let config: GeneratedContent
    let skillChain: [GeneratedWidgetSkillStep]
    let returns: String
    let ttl: Int
    let prompt: String?

    func toManifest(fallbackPrompt: String) throws -> WidgetManifest {
        guard let widgetType = WidgetType(rawValue: widgetType) else {
            throw WidgetManifestGenerationError.parseFailed("Unknown widget type '\(widgetType)'.")
        }

        let configDictionary = try GeneratedContentBridge.dictionary(from: config)
        let config = try decodeConfig(from: configDictionary, widgetType: widgetType)

        return WidgetManifest(
            id: UUID(uuidString: id ?? "") ?? UUID(),
            version: version,
            widgetType: widgetType,
            config: config,
            skillChain: try skillChain.map { try $0.toStep() },
            returns: returns,
            ttl: ttl,
            prompt: prompt?.isEmpty == false ? prompt! : fallbackPrompt
        )
    }

    private func decodeConfig(from dictionary: [String: Any], widgetType: WidgetType) throws -> WidgetConfig {
        let data = try JSONSerialization.data(withJSONObject: dictionary)
        let decoder = JSONDecoder()

        switch widgetType {
        case .barChart:
            return .barChart(try decoder.decode(BarChartConfig.self, from: data))
        case .lineChart:
            return .lineChart(try decoder.decode(LineChartConfig.self, from: data))
        case .statCard:
            return .statCard(try decoder.decode(StatCardConfig.self, from: data))
        case .table:
            return .table(try decoder.decode(TableConfig.self, from: data))
        case .list:
            return .list(try decoder.decode(ListConfig.self, from: data))
        case .text:
            return .text(try decoder.decode(TextConfig.self, from: data))
        case .priceCard:
            return .priceCard(try decoder.decode(PriceCardConfig.self, from: data))
        }
    }
}

@Generable(description: "A single widget skill step.")
struct GeneratedWidgetSkillStep: Sendable {
    let step: Int
    let skill: String
    let params: GeneratedContent
    let outputKey: String

    func toStep() throws -> WidgetSkillStep {
        guard let skill = WidgetSkillName(rawValue: skill) else {
            throw WidgetManifestGenerationError.parseFailed("Unknown widget skill '\(skill)'.")
        }

        return WidgetSkillStep(
            step: step,
            skill: skill,
            params: try GeneratedContentBridge.anyCodableDictionary(from: params),
            outputKey: outputKey
        )
    }
}

final class OnDeviceWidgetManifestGenerator: @unchecked Sendable, WidgetManifestGenerator {
    typealias CompletionProvider = @Sendable ([ChatMessage], String) async throws -> GeneratedWidgetManifest

    private let completionProvider: CompletionProvider

    init(completionProvider: CompletionProvider? = nil) {
        self.completionProvider = completionProvider ?? { messages, instructions in
            try await OnDeviceLLM.shared.complete(
                messages: messages,
                instructions: instructions,
                generating: GeneratedWidgetManifest.self
            )
        }
    }

    func generate(prompt: String) async throws -> WidgetManifest {
        let response: GeneratedWidgetManifest
        do {
            response = try await completionProvider([.user(prompt)], WidgetManifestSystemPrompt.build())
        } catch {
            throw WidgetManifestGenerationError.llmFailed(error.localizedDescription)
        }

        do {
            let manifest = try response.toManifest(fallbackPrompt: prompt)
            return try WidgetManifestValidator.validate(manifest)
        } catch let error as WidgetManifestValidationError {
            throw WidgetManifestGenerationError.validationFailed(error.localizedDescription)
        } catch {
            throw WidgetManifestGenerationError.parseFailed(error.localizedDescription)
        }
    }
}

enum WidgetManifestGenerationError: LocalizedError, Equatable {
    case llmFailed(String)
    case parseFailed(String)
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .llmFailed(let detail):
            return "Widget generation failed: \(detail)"
        case .parseFailed(let detail):
            return "Failed to parse widget manifest: \(detail)"
        case .validationFailed(let detail):
            return "Generated widget manifest is invalid: \(detail)"
        }
    }
}

enum WidgetManifestSystemPrompt {
    static func build() -> String {
        """
        You are a widget generation agent for the Wheel browser.

        Return a single structured WidgetManifest matching the schema below.
        Generate only free, no-auth data sources. Prefer public JSON APIs over scraping.

        Widget types:
        - barChart
        - lineChart
        - statCard
        - table
        - list
        - text
        - priceCard

        Skill names:
        - fetchUrl
        - parseHtml
        - parseJson
        - extractWithRegex
        - parseCsv
        - transform
        - filterSort
        - mergeArrays
        - computeStats

        Rules:
        - version must be "1"
        - step numbers must be sequential starting at 1
        - fetchUrl.url must be a static HTTPS URL
        - returns must match an outputKey
        - ttl should be 300 for prices, 3600 for weather, 86400 for static data, 0 for realtime data
        - output only structured data
        """
    }
}
