import Foundation
import FoundationModels

struct WidgetManifestGenerationProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case checkingAvailability
        case generatingManifest
        case repairingManifest
        case validatingManifest
    }

    let phase: Phase
    let detail: String
}

typealias WidgetManifestGenerationProgressHandler = @Sendable (WidgetManifestGenerationProgress) async -> Void

protocol WidgetManifestGenerator: Sendable {
    func generate(prompt: String, progress: WidgetManifestGenerationProgressHandler?) async throws -> WidgetManifest
}

extension WidgetManifestGenerator {
    func generate(prompt: String) async throws -> WidgetManifest {
        try await generate(prompt: prompt, progress: nil)
    }
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
        try WidgetManifestNormalizer.normalize(self, fallbackPrompt: fallbackPrompt)
    }
}

@Generable(description: "A single widget skill step.")
struct GeneratedWidgetSkillStep: Sendable {
    let step: Int
    let skill: String
    let params: GeneratedContent
    let outputKey: String

    func toStep() throws -> WidgetSkillStep {
        try WidgetManifestNormalizer.normalize(step: self)
    }
}

final class OnDeviceWidgetManifestGenerator: @unchecked Sendable, WidgetManifestGenerator {
    typealias CompletionProvider = @Sendable ([ChatMessage], String) async throws -> GeneratedWidgetManifest
    typealias AvailabilityProvider = @Sendable () async -> OnDeviceLLM.AvailabilityStatus

    private let completionProvider: CompletionProvider
    private let availabilityProvider: AvailabilityProvider?

    init(
        completionProvider: CompletionProvider? = nil,
        availabilityProvider: AvailabilityProvider? = nil
    ) {
        self.completionProvider = completionProvider ?? { messages, instructions in
            try await OnDeviceLLM.shared.complete(
                messages: messages,
                instructions: instructions,
                generating: GeneratedWidgetManifest.self
            )
        }
        if let availabilityProvider {
            self.availabilityProvider = availabilityProvider
        } else if completionProvider == nil {
            self.availabilityProvider = {
                await OnDeviceLLM.shared.availabilityStatus()
            }
        } else {
            self.availabilityProvider = nil
        }
    }

    func generate(prompt: String, progress: WidgetManifestGenerationProgressHandler? = nil) async throws -> WidgetManifest {
        let instructions = WidgetManifestSystemPrompt.build()
        if let template = WidgetPromptTemplateFactory.manifest(for: prompt) {
            await report(
                .generatingManifest,
                detail: "Using a built-in template for a reliable clock or time widget.",
                to: progress
            )
            await report(
                .validatingManifest,
                detail: "Validating the built-in manifest before saving.",
                to: progress
            )
            return try WidgetManifestValidator.validate(template)
        }

        if let availabilityProvider {
            await report(
                .checkingAvailability,
                detail: "Checking Apple Intelligence on this Mac.",
                to: progress
            )
            let availability = await availabilityProvider()
            guard availability.isAvailable else {
                throw WidgetManifestGenerationError.llmFailed(
                    availability.reason ?? "The on-device language model is not available."
                )
            }
        }

        await report(
            .generatingManifest,
            detail: "Drafting a widget manifest from your prompt.",
            to: progress
        )
        let response = try await requestManifest(
            messages: [.user(prompt)],
            instructions: instructions
        )

        do {
            await report(
                .validatingManifest,
                detail: "Validating the manifest schema and data pipeline.",
                to: progress
            )
            return try buildManifest(from: response, fallbackPrompt: prompt)
        } catch let error as WidgetManifestGenerationError {
            Log.Widgets.warning("Initial widget manifest was invalid, retrying repair: \(error.localizedDescription)")
            Log.Widgets.debug("Widget manifest candidate: \(rawManifestDebugString(from: response))")

            do {
                await report(
                    .repairingManifest,
                    detail: "Repairing the manifest because the first draft was invalid.",
                    to: progress
                )
                let repaired = try await requestManifest(
                    messages: repairMessages(
                        prompt: prompt,
                        response: response,
                        failure: error
                    ),
                    instructions: instructions
                )
                await report(
                    .validatingManifest,
                    detail: "Validating the repaired manifest before saving.",
                    to: progress
                )
                return try buildManifest(from: repaired, fallbackPrompt: prompt)
            } catch let repairError as WidgetManifestGenerationError {
                Log.Widgets.error("Widget manifest repair failed", error: repairError)
                throw repairError
            } catch {
                Log.Widgets.error("Widget manifest repair request failed", error: error)
                throw error
            }
        }
    }

    private func requestManifest(
        messages: [ChatMessage],
        instructions: String
    ) async throws -> GeneratedWidgetManifest {
        do {
            return try await completionProvider(messages, instructions)
        } catch {
            throw WidgetManifestGenerationError.llmFailed(error.localizedDescription)
        }
    }

    private func buildManifest(
        from response: GeneratedWidgetManifest,
        fallbackPrompt: String
    ) throws -> WidgetManifest {
        do {
            let manifest = try response.toManifest(fallbackPrompt: fallbackPrompt)
            return try WidgetManifestValidator.validate(manifest)
        } catch let error as WidgetManifestGenerationError {
            throw error
        } catch let error as WidgetManifestValidationError {
            throw WidgetManifestGenerationError.validationFailed(error.localizedDescription)
        } catch {
            throw WidgetManifestGenerationError.parseFailed(error.localizedDescription)
        }
    }

    private func repairMessages(
        prompt: String,
        response: GeneratedWidgetManifest,
        failure: WidgetManifestGenerationError
    ) -> [ChatMessage] {
        let rawManifest = rawManifestDebugString(from: response)
        let repairPrompt = """
        The previous widget manifest was invalid. Repair it and return a single corrected WidgetManifest.

        Original user request:
        \(prompt)

        Validation/parsing error:
        \(failure.localizedDescription)

        Invalid manifest:
        \(rawManifest)

        Keep the same intent, use only the allowed widget types and skills, and make the config/schema exact.
        """

        return [
            .user(prompt),
            .assistant(rawManifest),
            .user(repairPrompt),
        ]
    }

    private func rawManifestDebugString(from response: GeneratedWidgetManifest) -> String {
        GeneratedContentBridge.prettyJSONString(from: response) ?? "<unavailable>"
    }

    private func report(
        _ phase: WidgetManifestGenerationProgress.Phase,
        detail: String,
        to progress: WidgetManifestGenerationProgressHandler?
    ) async {
        guard let progress else { return }
        await progress(.init(phase: phase, detail: detail))
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
        You generate a single WidgetManifest for the Wheel browser.

        Return only structured data. No prose. No markdown fences. Prefer free public JSON APIs over scraping.

        Manifest contract:
        - id: UUID string
        - version: "1"
        - widgetType: one of [barChart, lineChart, statCard, table, list, text, priceCard]
        - config: must exactly match the selected widget type schema below
        - skillChain: ordered steps using only the allowed skills below
        - returns: must exactly match an outputKey from skillChain
        - ttl: 300 for prices, 3600 for weather, 86400 for static data, 0 for real-time
        - prompt: echo the original user request

        Allowed skills and required param names:
        - currentDateTime { timeZone?, locale?, label?, showTimeZone?, includeSeconds?, dateStyle?, timeStyle?, hour12? }
        - fetchUrl { url, method?, headers?, body? } where url is a static HTTPS URL
        - parseHtml { html, selector, attribute?, extractText?, limit? }
        - parseJson { json, path? }
        - extractWithRegex { text, pattern, flags?, group? }
        - parseCsv { csv, hasHeader?, delimiter? }
        - transform { data, mapping }
        - filterSort { data, filter?, sortBy?, ascending?, limit? }
        - mergeArrays { arrays, joinKey?, label? }
        - computeStats { data, field, ops }

        Variable references:
        - Use "$outputKey" to pass the whole output of a prior step
        - Use "$outputKey.path.to.field" for nested access
        - Every referenced outputKey must come from an earlier step

        Widget config schemas:
        - barChart config: { title, xField, yField, color?, yPrefix?, yUnit? } and returned data must be object[]
        - lineChart config: { title, xField, series: [{ field, label, color? }], yPrefix?, showPoints? } and returned data must be object[]
        - statCard config: { title, valueField, prefix?, suffix?, changeField?, changeIsPercent? } and returned data must be a single object
        - table config: { title, columns: [{ field, header, prefix? }], maxRows? } and returned data must be object[]
        - list config: { title, labelField, valueField?, subtitleField?, badgeField?, captionField?, iconField?, linkField?, maxItems?, variant? } and returned data must be object[]
        - text config: { title?, markdown } and returned data must be { content: string }
        - priceCard config: { title, priceField, changeField?, changePercentField?, prefix?, footnote? } and returned data must be a single object

        Practical guidance:
        - For clocks, world clocks, and timezone widgets, use currentDateTime with an IANA timezone like America/Los_Angeles
        - For multi-clock widgets, use one currentDateTime step per location and a final transform step to combine them into a list or table
        - Do not use external time APIs or regex parsing for clocks
        - For JSON APIs, prefer fetchUrl -> parseJson -> transform/filterSort/computeStats
        - For text widgets, prefer one transform step that returns { content: ... }
        - For lists, use compact for simple summaries, ranked for leaderboards/watchlists, feed for headlines/updates, agenda for schedules, and cards for richer multi-line items
        - Prefer CoinGecko, Open-Meteo, wttr.in?format=j1, Frankfurter, REST Countries, Numbers API, and similar no-auth sources
        - Avoid APIs requiring auth keys and avoid unstable scraping targets unless no reliable API exists

        Hard rules:
        - Step numbers must be sequential starting at 1
        - Every outputKey must be unique
        - fetchUrl.url must be a literal HTTPS URL, never a $ref
        - Use exact field names from the schemas above; do not invent aliases
        - Output only the manifest object
        """
    }
}

private enum WidgetManifestNormalizer {
    static func normalize(_ raw: GeneratedWidgetManifest, fallbackPrompt: String) throws -> WidgetManifest {
        let resolvedPrompt = raw.prompt?.nonEmptyTrimmed ?? fallbackPrompt
        let widgetType = try canonicalWidgetType(from: raw.widgetType)
        var configDictionary = try GeneratedContentBridge.dictionary(from: raw.config)
        normalizeConfig(&configDictionary, for: widgetType, fallbackTitle: resolvedPrompt)
        let config = try decodeConfig(from: configDictionary, widgetType: widgetType)

        let steps = try raw.skillChain.map { try normalize(step: $0) }
        let returns = try normalizedReturnKey(raw.returns)

        return WidgetManifest(
            id: UUID(uuidString: raw.id?.nonEmptyTrimmed ?? "") ?? UUID(),
            version: raw.version.trimmingCharacters(in: .whitespacesAndNewlines),
            widgetType: widgetType,
            config: config,
            skillChain: steps,
            returns: returns,
            ttl: raw.ttl,
            prompt: resolvedPrompt
        )
    }

    static func normalize(step raw: GeneratedWidgetSkillStep) throws -> WidgetSkillStep {
        let skill = try canonicalSkillName(from: raw.skill)
        var params = try GeneratedContentBridge.dictionary(from: raw.params)
        normalizeParams(&params, for: skill)
        params = normalizeReferences(in: params)

        return WidgetSkillStep(
            step: raw.step,
            skill: skill,
            params: params.mapValues(AnyCodable.init),
            outputKey: try normalizedOutputKey(raw.outputKey)
        )
    }

    private static func decodeConfig(from dictionary: [String: Any], widgetType: WidgetType) throws -> WidgetConfig {
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

    private static func canonicalWidgetType(from rawValue: String) throws -> WidgetType {
        if let exact = WidgetType(rawValue: rawValue) {
            return exact
        }

        switch normalizedIdentifier(rawValue) {
        case "barchart", "bargraph":
            return .barChart
        case "linechart", "timeseries", "trendchart":
            return .lineChart
        case "statcard", "statscard", "metriccard", "metric":
            return .statCard
        case "table", "datatable":
            return .table
        case "list", "rankinglist":
            return .list
        case "text", "textcard", "markdown", "note":
            return .text
        case "pricecard", "price", "ticker", "quote":
            return .priceCard
        default:
            throw WidgetManifestGenerationError.parseFailed("Unknown widget type '\(rawValue)'.")
        }
    }

    private static func canonicalSkillName(from rawValue: String) throws -> WidgetSkillName {
        if let exact = WidgetSkillName(rawValue: rawValue) {
            return exact
        }

        switch normalizedIdentifier(rawValue) {
        case "currentdatetime", "currenttime", "datetime", "clock", "time":
            return .currentDateTime
        case "fetchurl", "fetch", "httpfetch", "request":
            return .fetchUrl
        case "parsehtml", "htmlparse", "scrapehtml":
            return .parseHtml
        case "parsejson", "jsonparse", "json":
            return .parseJson
        case "extractwithregex", "regex", "regexextract":
            return .extractWithRegex
        case "parsecsv", "csvparse", "csv":
            return .parseCsv
        case "transform", "mapfields", "map", "reshape":
            return .transform
        case "filtersort", "filter", "sort":
            return .filterSort
        case "mergearrays", "merge", "joinarrays":
            return .mergeArrays
        case "computestats", "stats", "aggregate":
            return .computeStats
        default:
            throw WidgetManifestGenerationError.parseFailed("Unknown widget skill '\(rawValue)'.")
        }
    }

    private static func normalizeConfig(
        _ config: inout [String: Any],
        for widgetType: WidgetType,
        fallbackTitle: String
    ) {
        switch widgetType {
        case .barChart:
            setIfMissing(&config, key: "title", value: string(in: config, keys: ["heading", "name"]) ?? fallbackTitle)
            setIfMissing(&config, key: "xField", value: string(in: config, keys: ["labelField", "dateField", "categoryField"]))
            setIfMissing(&config, key: "yField", value: string(in: config, keys: ["valueField", "priceField", "metricField"]))
        case .lineChart:
            setIfMissing(&config, key: "title", value: string(in: config, keys: ["heading", "name"]) ?? fallbackTitle)
            setIfMissing(&config, key: "xField", value: string(in: config, keys: ["labelField", "dateField", "timeField"]))
            if config["series"] == nil {
                if let yField = string(in: config, keys: ["yField", "valueField", "priceField"]) {
                    config["series"] = [[
                        "field": yField,
                        "label": string(in: config, keys: ["seriesLabel", "label"]) ?? prettifyFieldName(yField),
                        "color": string(in: config, keys: ["color"]),
                    ].compactMapValues { $0 }]
                }
            } else if let normalizedSeries = normalizedSeries(from: config["series"]) {
                config["series"] = normalizedSeries
            }
        case .statCard:
            setIfMissing(&config, key: "title", value: string(in: config, keys: ["heading", "name"]) ?? fallbackTitle)
            setIfMissing(&config, key: "valueField", value: string(in: config, keys: ["value", "field", "metricField", "primaryField", "priceField"]) ?? "value")
            if config["changeIsPercent"] == nil, let suffix = string(in: config, keys: ["suffix"]), suffix == "%" {
                config["changeIsPercent"] = true
            }
            setIfMissing(&config, key: "changeField", value: string(in: config, keys: ["deltaField", "differenceField"]))
        case .table:
            setIfMissing(&config, key: "title", value: string(in: config, keys: ["heading", "name"]) ?? fallbackTitle)
            if config["columns"] == nil, let columns = normalizedColumns(from: config) {
                config["columns"] = columns
            } else if let columns = normalizedColumns(from: config) {
                config["columns"] = columns
            }
            setIfMissing(&config, key: "maxRows", value: int(in: config, keys: ["limit", "rows"]))
        case .list:
            setIfMissing(&config, key: "title", value: string(in: config, keys: ["heading", "name"]) ?? fallbackTitle)
            setIfMissing(&config, key: "labelField", value: string(in: config, keys: ["titleField", "nameField", "textField", "field"]) ?? "label")
            setIfMissing(&config, key: "valueField", value: string(in: config, keys: ["trailingField", "value", "detailField"]))
            setIfMissing(&config, key: "subtitleField", value: string(in: config, keys: ["secondaryField", "descriptionField", "summaryField"]))
            setIfMissing(&config, key: "badgeField", value: string(in: config, keys: ["statusField", "tagField", "pillField"]))
            setIfMissing(&config, key: "captionField", value: string(in: config, keys: ["metaField", "footerField", "captionField"]))
            setIfMissing(&config, key: "iconField", value: string(in: config, keys: ["emojiField", "imageField", "symbolField"]))
            setIfMissing(&config, key: "linkField", value: string(in: config, keys: ["urlField", "hrefField", "link", "linkField"]))
            setIfMissing(&config, key: "maxItems", value: int(in: config, keys: ["limit", "rows"]))
            if let variant = string(in: config, keys: ["variant", "layout", "style"]),
               let normalizedVariant = canonicalListVariant(from: variant) {
                config["variant"] = normalizedVariant
            }
        case .text:
            setIfMissing(&config, key: "title", value: string(in: config, keys: ["heading", "name"]))
            if config["markdown"] is String {
                config["markdown"] = bool(in: config, keys: ["markdown"]) ?? true
            }
            if config["markdown"] == nil {
                config["markdown"] = bool(in: config, keys: ["isMarkdown", "renderMarkdown", "richText"]) ?? false
            }
        case .priceCard:
            setIfMissing(&config, key: "title", value: string(in: config, keys: ["heading", "name"]) ?? fallbackTitle)
            setIfMissing(&config, key: "priceField", value: string(in: config, keys: ["valueField", "value", "field"]) ?? "price")
            setIfMissing(&config, key: "changeField", value: string(in: config, keys: ["deltaField", "differenceField"]))
            setIfMissing(&config, key: "changePercentField", value: string(in: config, keys: ["percentField", "changePctField", "percentChangeField"]))
            setIfMissing(&config, key: "footnote", value: string(in: config, keys: ["subtitle", "caption"]))
        }
    }

    private static func normalizeParams(_ params: inout [String: Any], for skill: WidgetSkillName) {
        switch skill {
        case .currentDateTime:
            setIfMissing(&params, key: "timeZone", value: string(in: params, keys: ["timezone", "tz", "zone"]))
            setIfMissing(&params, key: "locale", value: string(in: params, keys: ["language", "localeIdentifier"]))
            setIfMissing(&params, key: "label", value: string(in: params, keys: ["title", "name", "city", "location"]))
            setIfMissing(&params, key: "showTimeZone", value: bool(in: params, keys: ["showZone", "includeTimeZone", "includeZone"]))
            setIfMissing(&params, key: "includeSeconds", value: bool(in: params, keys: ["showSeconds", "seconds"]))
            setIfMissing(&params, key: "timeStyle", value: string(in: params, keys: ["timeFormat"]))
            setIfMissing(&params, key: "dateStyle", value: string(in: params, keys: ["dateFormat"]))
        case .fetchUrl:
            setIfMissing(&params, key: "url", value: string(in: params, keys: ["endpoint", "href", "link"]))
            if let method = string(in: params, keys: ["method"])?.uppercased() {
                params["method"] = method
            }
        case .parseHtml:
            setIfMissing(&params, key: "html", value: string(in: params, keys: ["input", "text", "raw"]))
            setIfMissing(&params, key: "selector", value: string(in: params, keys: ["cssSelector"]))
            setIfMissing(&params, key: "extractText", value: bool(in: params, keys: ["textOnly"]))
            setIfMissing(&params, key: "limit", value: int(in: params, keys: ["max"]))
        case .parseJson:
            setIfMissing(&params, key: "json", value: string(in: params, keys: ["input", "text", "raw", "data"]))
        case .extractWithRegex:
            setIfMissing(&params, key: "text", value: string(in: params, keys: ["input", "raw", "data"]))
            setIfMissing(&params, key: "pattern", value: string(in: params, keys: ["regex"]))
            setIfMissing(&params, key: "group", value: int(in: params, keys: ["captureGroup"]))
        case .parseCsv:
            setIfMissing(&params, key: "csv", value: string(in: params, keys: ["input", "text", "raw"]))
        case .transform:
            setIfMissing(&params, key: "data", value: params["input"] ?? params["items"] ?? params["source"])
            setIfMissing(&params, key: "mapping", value: params["map"] ?? params["fields"] ?? params["schema"])
        case .filterSort:
            setIfMissing(&params, key: "data", value: params["input"] ?? params["items"] ?? params["array"])
            setIfMissing(&params, key: "sortBy", value: string(in: params, keys: ["sort", "sortField"]))
            if params["ascending"] == nil {
                if let descending = bool(in: params, keys: ["descending"]) {
                    params["ascending"] = !descending
                } else if let order = string(in: params, keys: ["order"])?.lowercased() {
                    params["ascending"] = order != "desc"
                }
            }
            setIfMissing(&params, key: "limit", value: int(in: params, keys: ["max"]))
        case .mergeArrays:
            setIfMissing(&params, key: "arrays", value: params["inputs"] ?? params["sources"])
        case .computeStats:
            setIfMissing(&params, key: "data", value: params["input"] ?? params["items"] ?? params["array"])
            setIfMissing(&params, key: "field", value: string(in: params, keys: ["valueField", "metricField"]))
            if params["ops"] == nil, let op = string(in: params, keys: ["op"]) {
                params["ops"] = [op]
            }
        }
    }

    private static func normalizedSeries(from value: Any?) -> [[String: Any]]? {
        guard let values = value as? [Any] else { return nil }
        return values.compactMap { item in
            if let field = item as? String {
                return [
                    "field": field,
                    "label": prettifyFieldName(field),
                ]
            }

            guard let dictionary = item as? [String: Any] else { return nil }
            let field = string(in: dictionary, keys: ["field", "valueField", "key"])
            guard let field else { return nil }

            return [
                "field": field,
                "label": string(in: dictionary, keys: ["label", "name", "title"]) ?? prettifyFieldName(field),
                "color": string(in: dictionary, keys: ["color"]),
            ].compactMapValues { $0 }
        }
    }

    private static func normalizedColumns(from config: [String: Any]) -> [[String: Any]]? {
        if let columns = config["columns"] as? [Any] {
            return columns.compactMap { item in
                if let field = item as? String {
                    return [
                        "field": field,
                        "header": prettifyFieldName(field),
                    ]
                }

                guard let dictionary = item as? [String: Any] else { return nil }
                let field = string(in: dictionary, keys: ["field", "key", "valueField"])
                guard let field else { return nil }
                return [
                    "field": field,
                    "header": string(in: dictionary, keys: ["header", "label", "title"]) ?? prettifyFieldName(field),
                    "prefix": string(in: dictionary, keys: ["prefix"]),
                ].compactMapValues { $0 }
            }
        }

        guard let fields = stringArray(in: config, keys: ["fields", "headers"]) else { return nil }
        let headers = stringArray(in: config, keys: ["headers"])
        return fields.enumerated().map { index, field in
            [
                "field": field,
                "header": headers?[safe: index] ?? prettifyFieldName(field),
            ]
        }
    }

    private static func canonicalListVariant(from rawValue: String) -> String? {
        switch normalizedIdentifier(rawValue) {
        case "compact", "simple":
            return ListVariant.compact.rawValue
        case "ranked", "ranking", "leaderboard":
            return ListVariant.ranked.rawValue
        case "feed", "news", "updates":
            return ListVariant.feed.rawValue
        case "agenda", "schedule", "timeline":
            return ListVariant.agenda.rawValue
        case "cards", "card", "richcards":
            return ListVariant.cards.rawValue
        default:
            return nil
        }
    }

    private static func string(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String, let trimmed = value.nonEmptyTrimmed {
                return trimmed
            }
            if let value = dictionary[key] as? NSNumber {
                return value.stringValue
            }
        }
        return nil
    }

    private static func bool(in dictionary: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = dictionary[key] as? Bool {
                return value
            }
            if let value = dictionary[key] as? String {
                switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true", "yes", "1":
                    return true
                case "false", "no", "0":
                    return false
                default:
                    break
                }
            }
            if let value = dictionary[key] as? NSNumber {
                return value.boolValue
            }
        }
        return nil
    }

    private static func int(in dictionary: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = dictionary[key] as? Int {
                return value
            }
            if let value = dictionary[key] as? Double {
                return Int(value)
            }
            if let value = dictionary[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if let parsed = Int(trimmed) {
                    return parsed
                }
                let digits = trimmed.split(whereSeparator: { !$0.isNumber && $0 != "-" })
                if let candidate = digits.first, let parsed = Int(String(candidate)) {
                    return parsed
                }
            }
            if let value = dictionary[key] as? NSNumber {
                return value.intValue
            }
        }
        return nil
    }

    private static func normalizeReferences(in dictionary: [String: Any]) -> [String: Any] {
        dictionary.mapValues(normalizeReferenceValue)
    }

    private static func normalizeReferenceValue(_ value: Any) -> Any {
        switch value {
        case let string as String:
            return normalizedReferenceString(string)
        case let dictionary as [String: Any]:
            return normalizeReferences(in: dictionary)
        case let array as [Any]:
            return array.map(normalizeReferenceValue)
        default:
            return value
        }
    }

    private static func normalizedOutputKey(_ rawValue: String) throws -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw WidgetManifestGenerationError.parseFailed("Widget outputKey cannot be empty.")
        }

        var candidate = trimmed
        if candidate.hasPrefix("$") {
            let reference = normalizedReferenceString(candidate)
            candidate = String(reference.dropFirst())
        }

        candidate = stripPlaceholderPrefix(candidate)
        let root = candidate.split(separator: ".", omittingEmptySubsequences: true).first.map(String.init) ?? candidate
        let sanitized = sanitizeOutputKeyComponent(root)
        guard !sanitized.isEmpty else {
            throw WidgetManifestGenerationError.parseFailed("Widget outputKey '\(rawValue)' is invalid.")
        }
        return sanitized
    }

    private static func normalizedReturnKey(_ rawValue: String) throws -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw WidgetManifestGenerationError.parseFailed("Widget returns cannot be empty.")
        }

        if trimmed.hasPrefix("$") {
            let reference = normalizedReferenceString(trimmed)
            let body = String(reference.dropFirst())
            let root = body.split(separator: ".", omittingEmptySubsequences: true).first.map(String.init) ?? body
            let sanitized = sanitizeOutputKeyComponent(root)
            guard !sanitized.isEmpty else {
                throw WidgetManifestGenerationError.parseFailed("Widget returns '\(rawValue)' is invalid.")
            }
            return sanitized
        }

        return try normalizedOutputKey(trimmed)
    }

    private static func normalizedReferenceString(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("$") else {
            return trimmed
        }

        let body = stripPlaceholderPrefix(String(trimmed.dropFirst()))
        let components = body.split(separator: ".", omittingEmptySubsequences: true).map(String.init)
        guard let first = components.first else {
            return trimmed
        }

        let root = sanitizeOutputKeyComponent(first)
        let remainder = components.dropFirst().joined(separator: ".")
        if root.isEmpty {
            return trimmed
        }
        return remainder.isEmpty ? "$\(root)" : "$\(root).\(remainder)"
    }

    private static func stripPlaceholderPrefix(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercase = trimmed.lowercased()
        for prefix in ["outputkey.", "step.", "result.", "output."] {
            if lowercase.hasPrefix(prefix) {
                return String(trimmed.dropFirst(prefix.count))
            }
        }
        return trimmed
    }

    private static func sanitizeOutputKeyComponent(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private static func stringArray(in dictionary: [String: Any], keys: [String]) -> [String]? {
        for key in keys {
            if let values = dictionary[key] as? [String], !values.isEmpty {
                return values
            }
            if let values = dictionary[key] as? [Any] {
                let strings = values.compactMap { value -> String? in
                    if let string = value as? String {
                        return string.nonEmptyTrimmed
                    }
                    return nil
                }
                if !strings.isEmpty {
                    return strings
                }
            }
        }
        return nil
    }

    private static func setIfMissing(_ dictionary: inout [String: Any], key: String, value: Any?) {
        guard dictionary[key] == nil, let value else { return }
        dictionary[key] = value
    }

    private static func normalizedIdentifier(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func prettifyFieldName(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
