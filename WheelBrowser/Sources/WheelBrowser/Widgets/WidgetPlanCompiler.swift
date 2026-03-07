import Foundation
import FoundationModels

@Generable(description: "A constrained widget plan that will be compiled into a WidgetManifest.")
struct GeneratedWidgetPlan: Sendable {
    let title: String
    let widgetType: String
    let source: GeneratedWidgetSourcePlan
    let refreshSeconds: Int
    let prompt: String?
    let text: GeneratedWidgetTextPlan?
    let metric: GeneratedWidgetMetricPlan?
    let list: GeneratedWidgetListPlan?
    let table: GeneratedWidgetTablePlan?
    let chart: GeneratedWidgetChartPlan?

    func toManifest(fallbackPrompt: String) throws -> WidgetManifest {
        try WidgetPlanCompiler.compile(self, fallbackPrompt: fallbackPrompt)
    }
}

@Generable(description: "The source strategy for a widget plan.")
struct GeneratedWidgetSourcePlan: Sendable {
    let kind: String
    let url: String?
    let jsonPath: String?
    let resultShape: String?
    let sortBy: String?
    let sortAscending: Bool?
    let limit: Int?
    let timeZones: [GeneratedWidgetTimeZonePlan]?
}

@Generable(description: "A time zone entry for time-based widgets.")
struct GeneratedWidgetTimeZonePlan: Sendable {
    let label: String
    let identifier: String
}

@Generable(description: "Text widget display options.")
struct GeneratedWidgetTextPlan: Sendable {
    let contentField: String?
    let literalContent: String?
    let markdown: Bool?
    let showTimeZone: Bool?
    let includeSeconds: Bool?
}

@Generable(description: "Metric widget display options.")
struct GeneratedWidgetMetricPlan: Sendable {
    let valueField: String
    let changeField: String?
    let changePercentField: String?
    let changeIsPercent: Bool?
    let prefix: String?
    let suffix: String?
    let footnote: String?
}

@Generable(description: "List widget display options.")
struct GeneratedWidgetListPlan: Sendable {
    let variant: String?
    let labelField: String
    let valueField: String?
    let subtitleField: String?
    let badgeField: String?
    let captionField: String?
    let iconField: String?
    let linkField: String?
    let maxItems: Int?
}

@Generable(description: "Table widget display options.")
struct GeneratedWidgetTablePlan: Sendable {
    let columns: [GeneratedWidgetColumnPlan]
    let maxRows: Int?
}

@Generable(description: "A table column definition.")
struct GeneratedWidgetColumnPlan: Sendable {
    let field: String
    let header: String
    let prefix: String?
}

@Generable(description: "Chart widget display options.")
struct GeneratedWidgetChartPlan: Sendable {
    let xField: String
    let yField: String?
    let series: [GeneratedWidgetSeriesPlan]?
    let color: String?
    let yPrefix: String?
    let yUnit: String?
    let showPoints: Bool?
}

@Generable(description: "A chart series definition.")
struct GeneratedWidgetSeriesPlan: Sendable {
    let field: String
    let label: String
    let color: String?
}

enum WidgetPlanCompilationError: LocalizedError, Equatable {
    case unsupportedWidgetType(String)
    case unsupportedSourceKind(String)
    case unsupportedCombination(widgetType: String, sourceKind: String)
    case missingPlanSection(String)
    case invalidField(String)
    case invalidURL(String)
    case invalidTimeZones

    var errorDescription: String? {
        switch self {
        case .unsupportedWidgetType(let type):
            return "Unsupported widget type '\(type)' in widget plan."
        case .unsupportedSourceKind(let kind):
            return "Unsupported widget source kind '\(kind)' in widget plan."
        case .unsupportedCombination(let widgetType, let sourceKind):
            return "Widget type '\(widgetType)' is not supported with source kind '\(sourceKind)'."
        case .missingPlanSection(let section):
            return "Widget plan is missing required '\(section)' details."
        case .invalidField(let field):
            return "Widget plan field '\(field)' is invalid."
        case .invalidURL(let url):
            return "Widget plan URL '\(url)' is invalid."
        case .invalidTimeZones:
            return "Widget plan must include at least one valid time zone."
        }
    }
}

enum WidgetPlanCompiler {
    private enum SourceKind {
        case literalText
        case currentDateTime
        case jsonAPI
    }

    private enum ResultShape {
        case single
        case collection
    }

    private struct CanonicalTimeZone {
        let label: String
        let identifier: String

        var outputKey: String {
            label
                .lowercased()
                .replacingOccurrences(of: " ", with: "")
                .filter { $0.isLetter || $0.isNumber }
        }
    }

    private struct ResolvedListPresentation {
        let variant: ListVariant
        let labelField: String
        let valueField: String?
        let subtitleField: String?
        let badgeField: String?
        let captionField: String?
        let iconField: String?
        let linkField: String?
        let maxItems: Int?
    }

    static func compile(_ plan: GeneratedWidgetPlan, fallbackPrompt: String) throws -> WidgetManifest {
        let prompt = plan.prompt?.nonEmptyTrimmed ?? fallbackPrompt
        let title = plan.title.nonEmptyTrimmed ?? prompt
        let ttl = max(plan.refreshSeconds, 0)
        let widgetType = try canonicalWidgetType(plan.widgetType)
        let sourceKind = try canonicalSourceKind(plan.source.kind)

        switch sourceKind {
        case .literalText:
            return try compileLiteralText(plan, title: title, ttl: ttl, prompt: prompt)
        case .currentDateTime:
            return try compileCurrentDateTime(plan, widgetType: widgetType, title: title, ttl: ttl, prompt: prompt)
        case .jsonAPI:
            return try compileJSONAPI(plan, widgetType: widgetType, title: title, ttl: ttl, prompt: prompt)
        }
    }

    private static func compileLiteralText(
        _ plan: GeneratedWidgetPlan,
        title: String,
        ttl: Int,
        prompt: String
    ) throws -> WidgetManifest {
        guard try canonicalWidgetType(plan.widgetType) == .text else {
            throw WidgetPlanCompilationError.unsupportedCombination(widgetType: plan.widgetType, sourceKind: plan.source.kind)
        }
        guard let text = plan.text else {
            throw WidgetPlanCompilationError.missingPlanSection("text")
        }

        let content = text.literalContent?.nonEmptyTrimmed ?? prompt
        return WidgetManifest(
            widgetType: .text,
            config: .text(TextConfig(title: title, markdown: text.markdown ?? false)),
            skillChain: [
                WidgetSkillStep(
                    step: 1,
                    skill: .transform,
                    params: [
                        "data": AnyCodable(["content": content]),
                        "mapping": AnyCodable(["content": "content"]),
                    ],
                    outputKey: "textData"
                ),
            ],
            returns: "textData",
            ttl: ttl,
            prompt: prompt
        )
    }

    private static func compileCurrentDateTime(
        _ plan: GeneratedWidgetPlan,
        widgetType: WidgetType,
        title: String,
        ttl: Int,
        prompt: String
    ) throws -> WidgetManifest {
        let timeZones = try normalizedTimeZones(from: plan.source.timeZones)
        let resolvedWidgetType: WidgetType = (widgetType == .text && timeZones.count > 1) ? .list : widgetType

        if resolvedWidgetType == .text {
            let text = plan.text
            let zone = timeZones.first
            var params: [String: AnyCodable] = [
                "showTimeZone": AnyCodable(text?.showTimeZone ?? true),
                "includeSeconds": AnyCodable(text?.includeSeconds ?? true),
            ]
            if let zone {
                params["timeZone"] = AnyCodable(zone.identifier)
                params["label"] = AnyCodable(zone.label)
            }

            return WidgetManifest(
                widgetType: .text,
                config: .text(TextConfig(title: title, markdown: text?.markdown ?? false)),
                skillChain: [
                    WidgetSkillStep(
                        step: 1,
                        skill: .currentDateTime,
                        params: params,
                        outputKey: "clock"
                    ),
                ],
                returns: "clock",
                ttl: ttl,
                prompt: prompt
            )
        }

        switch resolvedWidgetType {
        case .list:
            let listPlan = plan.list
            var skillChain: [WidgetSkillStep] = []
            for (index, zone) in timeZones.enumerated() {
                skillChain.append(
                    WidgetSkillStep(
                        step: index + 1,
                        skill: .currentDateTime,
                        params: [
                            "timeZone": AnyCodable(zone.identifier),
                            "label": AnyCodable(zone.label),
                            "showTimeZone": AnyCodable(plan.text?.showTimeZone ?? true),
                            "includeSeconds": AnyCodable(plan.text?.includeSeconds ?? true),
                        ],
                        outputKey: "\(zone.outputKey)Clock"
                    )
                )
            }

            let refs = timeZones.map { "$\($0.outputKey)Clock" }
            skillChain.append(
                WidgetSkillStep(
                    step: skillChain.count + 1,
                    skill: .transform,
                    params: [
                        "data": AnyCodable(refs),
                        "mapping": AnyCodable([
                            "label": "label",
                            "value": "formatted",
                            "subtitle": "timeZoneAbbreviation",
                        ]),
                    ],
                    outputKey: "listData"
                )
            )

            return WidgetManifest(
                widgetType: .list,
                config: .list(
                    ListConfig(
                        title: title,
                        labelField: "label",
                        valueField: "value",
                        subtitleField: "subtitle",
                        badgeField: nil,
                        captionField: nil,
                        iconField: nil,
                        linkField: nil,
                        maxItems: listPlan?.maxItems ?? timeZones.count,
                        variant: canonicalListVariant(listPlan?.variant) ?? .compact
                    )
                ),
                skillChain: skillChain,
                returns: "listData",
                ttl: ttl,
                prompt: prompt
            )
        case .table:
            var skillChain: [WidgetSkillStep] = []
            for (index, zone) in timeZones.enumerated() {
                skillChain.append(
                    WidgetSkillStep(
                        step: index + 1,
                        skill: .currentDateTime,
                        params: [
                            "timeZone": AnyCodable(zone.identifier),
                            "label": AnyCodable(zone.label),
                            "showTimeZone": AnyCodable(plan.text?.showTimeZone ?? true),
                            "includeSeconds": AnyCodable(plan.text?.includeSeconds ?? true),
                        ],
                        outputKey: "\(zone.outputKey)Clock"
                    )
                )
            }

            let refs = timeZones.map { "$\($0.outputKey)Clock" }
            skillChain.append(
                WidgetSkillStep(
                    step: skillChain.count + 1,
                    skill: .transform,
                    params: [
                        "data": AnyCodable(refs),
                        "mapping": AnyCodable([
                            "column_0": "label",
                            "column_1": "time",
                            "column_2": "timeZoneAbbreviation",
                        ]),
                    ],
                    outputKey: "tableRows"
                )
            )

            return WidgetManifest(
                widgetType: .table,
                config: .table(
                    TableConfig(
                        title: title,
                        columns: [
                            TableColumnConfig(field: "column_0", header: "Location", prefix: nil),
                            TableColumnConfig(field: "column_1", header: "Time", prefix: nil),
                            TableColumnConfig(field: "column_2", header: "Zone", prefix: nil),
                        ],
                        maxRows: timeZones.count
                    )
                ),
                skillChain: skillChain,
                returns: "tableRows",
                ttl: ttl,
                prompt: prompt
            )
        default:
            throw WidgetPlanCompilationError.unsupportedCombination(widgetType: resolvedWidgetType.rawValue, sourceKind: plan.source.kind)
        }
    }

    private static func compileJSONAPI(
        _ plan: GeneratedWidgetPlan,
        widgetType: WidgetType,
        title: String,
        ttl: Int,
        prompt: String
    ) throws -> WidgetManifest {
        guard let urlString = plan.source.url?.nonEmptyTrimmed,
              let url = URL(string: urlString) else {
            throw WidgetPlanCompilationError.invalidURL(plan.source.url ?? "")
        }
        try WidgetNetworkPolicy.validateRemoteURL(url)

        let shape = canonicalResultShape(plan.source.resultShape, widgetType: widgetType)
        var steps: [WidgetSkillStep] = [
            WidgetSkillStep(
                step: 1,
                skill: .fetchUrl,
                params: ["url": AnyCodable(urlString)],
                outputKey: "raw"
            ),
        ]

        var currentKey = "sourceData"
        var parseParams: [String: AnyCodable] = [
            "json": AnyCodable("$raw"),
        ]
        if let jsonPath = plan.source.jsonPath?.nonEmptyTrimmed {
            parseParams["path"] = AnyCodable(jsonPath)
        }
        steps.append(
            WidgetSkillStep(
                step: 2,
                skill: .parseJson,
                params: parseParams,
                outputKey: currentKey
            )
        )

        if shape == .collection,
           (plan.source.sortBy?.nonEmptyTrimmed != nil || plan.source.limit != nil) {
            var filterParams: [String: AnyCodable] = [
                "data": AnyCodable("$\(currentKey)"),
                "ascending": AnyCodable(plan.source.sortAscending ?? true),
            ]
            if let sortBy = plan.source.sortBy?.nonEmptyTrimmed {
                filterParams["sortBy"] = AnyCodable(sortBy)
            }
            if let limit = plan.source.limit {
                filterParams["limit"] = AnyCodable(limit)
            }
            steps.append(
                WidgetSkillStep(
                    step: steps.count + 1,
                    skill: .filterSort,
                    params: filterParams,
                    outputKey: "filteredData"
                )
            )
            currentKey = "filteredData"
        }

        if shape == .collection, widgetType == .statCard || widgetType == .priceCard || widgetType == .text {
            steps.append(
                WidgetSkillStep(
                    step: steps.count + 1,
                    skill: .parseJson,
                    params: [
                        "json": AnyCodable("$\(currentKey)"),
                        "path": AnyCodable("[0]"),
                    ],
                    outputKey: "selectedItem"
                )
            )
            currentKey = "selectedItem"
        }

        switch widgetType {
        case .text:
            return try compileJSONText(plan, title: title, ttl: ttl, prompt: prompt, steps: steps, dataKey: currentKey)
        case .statCard:
            return try compileStatCard(plan, title: title, ttl: ttl, prompt: prompt, steps: steps, dataKey: currentKey)
        case .priceCard:
            return try compilePriceCard(plan, title: title, ttl: ttl, prompt: prompt, steps: steps, dataKey: currentKey)
        case .list:
            guard shape == .collection else {
                throw WidgetPlanCompilationError.unsupportedCombination(widgetType: widgetType.rawValue, sourceKind: "\(plan.source.kind)/single")
            }
            return try compileList(plan, title: title, ttl: ttl, prompt: prompt, steps: steps, dataKey: currentKey)
        case .table:
            guard shape == .collection else {
                throw WidgetPlanCompilationError.unsupportedCombination(widgetType: widgetType.rawValue, sourceKind: "\(plan.source.kind)/single")
            }
            return try compileTable(plan, title: title, ttl: ttl, prompt: prompt, steps: steps, dataKey: currentKey)
        case .barChart:
            guard shape == .collection else {
                throw WidgetPlanCompilationError.unsupportedCombination(widgetType: widgetType.rawValue, sourceKind: "\(plan.source.kind)/single")
            }
            return try compileBarChart(plan, title: title, ttl: ttl, prompt: prompt, steps: steps, dataKey: currentKey)
        case .lineChart:
            guard shape == .collection else {
                throw WidgetPlanCompilationError.unsupportedCombination(widgetType: widgetType.rawValue, sourceKind: "\(plan.source.kind)/single")
            }
            return try compileLineChart(plan, title: title, ttl: ttl, prompt: prompt, steps: steps, dataKey: currentKey)
        }
    }

    private static func compileJSONText(
        _ plan: GeneratedWidgetPlan,
        title: String,
        ttl: Int,
        prompt: String,
        steps: [WidgetSkillStep],
        dataKey: String
    ) throws -> WidgetManifest {
        guard let text = plan.text else {
            throw WidgetPlanCompilationError.missingPlanSection("text")
        }
        let contentField = text.contentField?.nonEmptyTrimmed ?? "content"
        let finalStep = WidgetSkillStep(
            step: steps.count + 1,
            skill: .transform,
            params: [
                "data": AnyCodable("$\(dataKey)"),
                "mapping": AnyCodable(["content": contentField]),
            ],
            outputKey: "textData"
        )

        return WidgetManifest(
            widgetType: .text,
            config: .text(TextConfig(title: title, markdown: text.markdown ?? false)),
            skillChain: steps + [finalStep],
            returns: "textData",
            ttl: ttl,
            prompt: prompt
        )
    }

    private static func compileStatCard(
        _ plan: GeneratedWidgetPlan,
        title: String,
        ttl: Int,
        prompt: String,
        steps: [WidgetSkillStep],
        dataKey: String
    ) throws -> WidgetManifest {
        guard let metric = plan.metric else {
            throw WidgetPlanCompilationError.missingPlanSection("metric")
        }
        guard let valueField = metric.valueField.nonEmptyTrimmed else {
            throw WidgetPlanCompilationError.invalidField("metric.valueField")
        }

        var mapping: [String: String] = ["value": valueField]
        if let changeField = metric.changeField?.nonEmptyTrimmed {
            mapping["change"] = changeField
        }

        let finalStep = WidgetSkillStep(
            step: steps.count + 1,
            skill: .transform,
            params: [
                "data": AnyCodable("$\(dataKey)"),
                "mapping": AnyCodable(mapping),
            ],
            outputKey: "cardData"
        )

        return WidgetManifest(
            widgetType: .statCard,
            config: .statCard(
                StatCardConfig(
                    title: title,
                    valueField: "value",
                    prefix: metric.prefix?.nonEmptyTrimmed,
                    suffix: metric.suffix?.nonEmptyTrimmed,
                    changeField: mapping["change"] == nil ? nil : "change",
                    changeIsPercent: metric.changeIsPercent
                )
            ),
            skillChain: steps + [finalStep],
            returns: "cardData",
            ttl: ttl,
            prompt: prompt
        )
    }

    private static func compilePriceCard(
        _ plan: GeneratedWidgetPlan,
        title: String,
        ttl: Int,
        prompt: String,
        steps: [WidgetSkillStep],
        dataKey: String
    ) throws -> WidgetManifest {
        guard let metric = plan.metric else {
            throw WidgetPlanCompilationError.missingPlanSection("metric")
        }
        guard let valueField = metric.valueField.nonEmptyTrimmed else {
            throw WidgetPlanCompilationError.invalidField("metric.valueField")
        }

        var mapping: [String: String] = ["price": valueField]
        if let changeField = metric.changeField?.nonEmptyTrimmed {
            mapping["change"] = changeField
        }
        if let changePercentField = metric.changePercentField?.nonEmptyTrimmed {
            mapping["changePercent"] = changePercentField
        }

        let finalStep = WidgetSkillStep(
            step: steps.count + 1,
            skill: .transform,
            params: [
                "data": AnyCodable("$\(dataKey)"),
                "mapping": AnyCodable(mapping),
            ],
            outputKey: "priceData"
        )

        return WidgetManifest(
            widgetType: .priceCard,
            config: .priceCard(
                PriceCardConfig(
                    title: title,
                    priceField: "price",
                    changeField: mapping["change"] == nil ? nil : "change",
                    changePercentField: mapping["changePercent"] == nil ? nil : "changePercent",
                    prefix: metric.prefix?.nonEmptyTrimmed,
                    footnote: metric.footnote?.nonEmptyTrimmed
                )
            ),
            skillChain: steps + [finalStep],
            returns: "priceData",
            ttl: ttl,
            prompt: prompt
        )
    }

    private static func compileList(
        _ plan: GeneratedWidgetPlan,
        title: String,
        ttl: Int,
        prompt: String,
        steps: [WidgetSkillStep],
        dataKey: String
    ) throws -> WidgetManifest {
        let list = try resolveListPresentation(plan, title: title, prompt: prompt)

        var mapping: [String: String] = [
            "label": list.labelField,
        ]
        if let valueField = list.valueField {
            mapping["value"] = valueField
        }
        if let subtitleField = list.subtitleField {
            mapping["subtitle"] = subtitleField
        }
        if let badgeField = list.badgeField {
            mapping["badge"] = badgeField
        }
        if let captionField = list.captionField {
            mapping["caption"] = captionField
        }
        if let iconField = list.iconField {
            mapping["icon"] = iconField
        }
        if let linkField = list.linkField {
            mapping["link"] = linkField
        }

        let finalStep = WidgetSkillStep(
            step: steps.count + 1,
            skill: .transform,
            params: [
                "data": AnyCodable("$\(dataKey)"),
                "mapping": AnyCodable(mapping),
            ],
            outputKey: "listData"
        )

        return WidgetManifest(
            widgetType: .list,
            config: .list(
                ListConfig(
                    title: title,
                    labelField: "label",
                    valueField: mapping["value"] == nil ? nil : "value",
                    subtitleField: mapping["subtitle"] == nil ? nil : "subtitle",
                    badgeField: mapping["badge"] == nil ? nil : "badge",
                    captionField: mapping["caption"] == nil ? nil : "caption",
                    iconField: mapping["icon"] == nil ? nil : "icon",
                    linkField: mapping["link"] == nil ? nil : "link",
                    maxItems: list.maxItems,
                    variant: list.variant
                )
            ),
            skillChain: steps + [finalStep],
            returns: "listData",
            ttl: ttl,
            prompt: prompt
        )
    }

    private static func resolveListPresentation(
        _ plan: GeneratedWidgetPlan,
        title: String,
        prompt: String
    ) throws -> ResolvedListPresentation {
        let raw = plan.list
        let hints = listInferenceHints(title: title, prompt: prompt, url: plan.source.url)

        guard let labelField = raw?.labelField.nonEmptyTrimmed ?? inferredListLabelField(from: hints) else {
            throw WidgetPlanCompilationError.missingPlanSection("list")
        }

        let valueField = raw?.valueField?.nonEmptyTrimmed ?? inferredListValueField(from: plan, hints: hints)
        let badgeField = raw?.badgeField?.nonEmptyTrimmed ?? inferredListBadgeField(from: plan)

        return ResolvedListPresentation(
            variant: canonicalListVariant(raw?.variant) ?? inferredListVariant(from: hints),
            labelField: labelField,
            valueField: valueField,
            subtitleField: raw?.subtitleField?.nonEmptyTrimmed ?? inferredListSubtitleField(from: hints),
            badgeField: badgeField,
            captionField: raw?.captionField?.nonEmptyTrimmed,
            iconField: raw?.iconField?.nonEmptyTrimmed,
            linkField: raw?.linkField?.nonEmptyTrimmed ?? inferredListLinkField(from: hints),
            maxItems: raw?.maxItems ?? plan.source.limit
        )
    }

    private static func compileTable(
        _ plan: GeneratedWidgetPlan,
        title: String,
        ttl: Int,
        prompt: String,
        steps: [WidgetSkillStep],
        dataKey: String
    ) throws -> WidgetManifest {
        guard let table = plan.table, !table.columns.isEmpty else {
            throw WidgetPlanCompilationError.missingPlanSection("table")
        }

        let mappings = Dictionary(uniqueKeysWithValues: try table.columns.enumerated().map { index, column in
            guard let field = column.field.nonEmptyTrimmed else {
                throw WidgetPlanCompilationError.invalidField("table.columns[\(index)].field")
            }
            return ("column_\(index)", field)
        })
        let finalStep = WidgetSkillStep(
            step: steps.count + 1,
            skill: .transform,
            params: [
                "data": AnyCodable("$\(dataKey)"),
                "mapping": AnyCodable(mappings),
            ],
            outputKey: "tableRows"
        )

        let columns = table.columns.enumerated().map { index, column in
            TableColumnConfig(
                field: "column_\(index)",
                header: column.header.nonEmptyTrimmed ?? "Column \(index + 1)",
                prefix: column.prefix?.nonEmptyTrimmed
            )
        }

        return WidgetManifest(
            widgetType: .table,
            config: .table(TableConfig(title: title, columns: columns, maxRows: table.maxRows ?? plan.source.limit)),
            skillChain: steps + [finalStep],
            returns: "tableRows",
            ttl: ttl,
            prompt: prompt
        )
    }

    private static func compileBarChart(
        _ plan: GeneratedWidgetPlan,
        title: String,
        ttl: Int,
        prompt: String,
        steps: [WidgetSkillStep],
        dataKey: String
    ) throws -> WidgetManifest {
        guard let chart = plan.chart,
              let xField = chart.xField.nonEmptyTrimmed,
              let yField = chart.yField?.nonEmptyTrimmed else {
            throw WidgetPlanCompilationError.missingPlanSection("chart")
        }

        let finalStep = WidgetSkillStep(
            step: steps.count + 1,
            skill: .transform,
            params: [
                "data": AnyCodable("$\(dataKey)"),
                "mapping": AnyCodable([
                    "x": xField,
                    "y": yField,
                ]),
            ],
            outputKey: "chartRows"
        )

        return WidgetManifest(
            widgetType: .barChart,
            config: .barChart(
                BarChartConfig(
                    title: title,
                    xField: "x",
                    yField: "y",
                    color: chart.color?.nonEmptyTrimmed,
                    yPrefix: chart.yPrefix?.nonEmptyTrimmed,
                    yUnit: chart.yUnit?.nonEmptyTrimmed
                )
            ),
            skillChain: steps + [finalStep],
            returns: "chartRows",
            ttl: ttl,
            prompt: prompt
        )
    }

    private static func compileLineChart(
        _ plan: GeneratedWidgetPlan,
        title: String,
        ttl: Int,
        prompt: String,
        steps: [WidgetSkillStep],
        dataKey: String
    ) throws -> WidgetManifest {
        guard let chart = plan.chart,
              let xField = chart.xField.nonEmptyTrimmed else {
            throw WidgetPlanCompilationError.missingPlanSection("chart")
        }

        let sourceSeries = canonicalSeries(from: chart)
        guard !sourceSeries.isEmpty else {
            throw WidgetPlanCompilationError.missingPlanSection("chart.series")
        }

        var mapping: [String: String] = ["x": xField]
        let series = sourceSeries.enumerated().map { index, series -> LineChartSeries in
            let field = "series_\(index)"
            mapping[field] = series.field
            return LineChartSeries(field: field, label: series.label, color: series.color)
        }

        let finalStep = WidgetSkillStep(
            step: steps.count + 1,
            skill: .transform,
            params: [
                "data": AnyCodable("$\(dataKey)"),
                "mapping": AnyCodable(mapping),
            ],
            outputKey: "chartRows"
        )

        return WidgetManifest(
            widgetType: .lineChart,
            config: .lineChart(
                LineChartConfig(
                    title: title,
                    xField: "x",
                    series: series,
                    yPrefix: chart.yPrefix?.nonEmptyTrimmed,
                    showPoints: chart.showPoints
                )
            ),
            skillChain: steps + [finalStep],
            returns: "chartRows",
            ttl: ttl,
            prompt: prompt
        )
    }

    private static func normalizedTimeZones(from raw: [GeneratedWidgetTimeZonePlan]?) throws -> [CanonicalTimeZone] {
        let values = (raw ?? [])
            .compactMap { zone -> CanonicalTimeZone? in
                guard let label = zone.label.nonEmptyTrimmed,
                      let identifier = zone.identifier.nonEmptyTrimmed,
                      TimeZone(identifier: identifier) != nil else {
                    return nil
                }
                return CanonicalTimeZone(label: label, identifier: identifier)
            }

        guard !values.isEmpty else {
            throw WidgetPlanCompilationError.invalidTimeZones
        }
        return values
    }

    private static func canonicalSeries(from chart: GeneratedWidgetChartPlan) -> [GeneratedWidgetSeriesPlan] {
        if let series = chart.series, !series.isEmpty {
            return series.compactMap { entry in
                guard let field = entry.field.nonEmptyTrimmed,
                      let label = entry.label.nonEmptyTrimmed else {
                    return nil
                }
                return GeneratedWidgetSeriesPlan(field: field, label: label, color: entry.color?.nonEmptyTrimmed)
            }
        }
        if let yField = chart.yField?.nonEmptyTrimmed {
            return [
                GeneratedWidgetSeriesPlan(
                    field: yField,
                    label: yField
                        .replacingOccurrences(of: "_", with: " ")
                        .replacingOccurrences(of: "-", with: " ")
                        .capitalized,
                    color: chart.color
                ),
            ]
        }
        return []
    }

    private static func listInferenceHints(title: String, prompt: String, url: String?) -> String {
        [title, prompt, url ?? ""]
            .joined(separator: " ")
            .lowercased()
    }

    private static func inferredListVariant(from hints: String) -> ListVariant {
        if containsAny(["headline", "headlines", "news", "story", "stories", "article", "articles", "feed", "front page", "hacker news", "hackernews"], in: hints) {
            return .feed
        }
        if containsAny(["agenda", "schedule", "timeline", "events", "calendar"], in: hints) {
            return .agenda
        }
        if containsAny(["leaderboard", "ranking", "ranked", "watchlist", "top ", "best "], in: hints) {
            return .ranked
        }
        if containsAny(["cards", "card view", "rich"], in: hints) {
            return .cards
        }
        return .compact
    }

    private static func inferredListLabelField(from hints: String) -> String? {
        if containsAny(["crypto", "coin", "token", "stock", "ticker", "watchlist", "market"], in: hints) {
            return "name"
        }
        if containsAny(["headline", "headlines", "news", "story", "stories", "article", "articles", "feed", "front page", "hacker news", "hackernews"], in: hints) {
            return "title"
        }
        if containsAny(["agenda", "schedule", "event", "events"], in: hints) {
            return "title"
        }
        return "title"
    }

    private static func inferredListValueField(from plan: GeneratedWidgetPlan, hints: String) -> String? {
        guard let sortField = plan.source.sortBy?.nonEmptyTrimmed else {
            return containsAny(["price", "quote", "quotes"], in: hints) ? "price" : nil
        }

        if containsAny(["rank", "position"], in: sortField.lowercased()) {
            return nil
        }
        return sortField
    }

    private static func inferredListBadgeField(from plan: GeneratedWidgetPlan) -> String? {
        guard let sortField = plan.source.sortBy?.nonEmptyTrimmed else { return nil }
        if containsAny(["rank", "position"], in: sortField.lowercased()) {
            return sortField
        }
        return nil
    }

    private static func inferredListSubtitleField(from hints: String) -> String? {
        if containsAny(["headline", "headlines", "news", "story", "stories", "article", "articles", "feed", "front page", "hacker news", "hackernews"], in: hints) {
            return "author"
        }
        if containsAny(["crypto", "coin", "token", "stock", "ticker", "watchlist", "market"], in: hints) {
            return "symbol"
        }
        if containsAny(["agenda", "schedule", "event", "events"], in: hints) {
            return "time"
        }
        return nil
    }

    private static func inferredListLinkField(from hints: String) -> String? {
        if containsAny(["headline", "headlines", "news", "story", "stories", "article", "articles", "feed", "front page", "hacker news", "hackernews"], in: hints) {
            return "url"
        }
        return nil
    }

    private static func canonicalWidgetType(_ rawValue: String) throws -> WidgetType {
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
        case "list", "rankinglist", "feed":
            return .list
        case "text", "textcard", "markdown", "note":
            return .text
        case "pricecard", "price", "ticker", "quote":
            return .priceCard
        default:
            throw WidgetPlanCompilationError.unsupportedWidgetType(rawValue)
        }
    }

    private static func canonicalSourceKind(_ rawValue: String) throws -> SourceKind {
        switch normalizedIdentifier(rawValue) {
        case "literaltext", "literal", "note", "statictext":
            return .literalText
        case "currentdatetime", "clock", "time", "timezone", "worldclock":
            return .currentDateTime
        case "jsonapi", "json", "httpjson", "api":
            return .jsonAPI
        default:
            throw WidgetPlanCompilationError.unsupportedSourceKind(rawValue)
        }
    }

    private static func canonicalResultShape(_ rawValue: String?, widgetType: WidgetType) -> ResultShape {
        if let rawValue {
            switch normalizedIdentifier(rawValue) {
            case "collection", "list", "array", "many":
                return .collection
            case "single", "object", "one":
                return .single
            default:
                break
            }
        }

        switch widgetType {
        case .list, .table, .barChart, .lineChart:
            return .collection
        case .text, .statCard, .priceCard:
            return .single
        }
    }

    private static func canonicalListVariant(_ rawValue: String?) -> ListVariant? {
        guard let rawValue else { return nil }
        switch normalizedIdentifier(rawValue) {
        case "compact", "simple":
            return .compact
        case "ranked", "ranking", "leaderboard":
            return .ranked
        case "feed", "news", "updates":
            return .feed
        case "agenda", "schedule", "timeline":
            return .agenda
        case "cards", "card", "richcards":
            return .cards
        default:
            return nil
        }
    }

    private static func normalizedIdentifier(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func containsAny(_ needles: [String], in haystack: String) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}

enum WidgetPlanSystemPrompt {
    static func build() -> String {
        """
        You generate a constrained WidgetPlan for the Wheel browser.

        Return only structured data. No prose. No markdown fences. Do not emit a raw WidgetManifest or a skillChain.

        Allowed widget types:
        - barChart
        - lineChart
        - statCard
        - table
        - list
        - text
        - priceCard

        Allowed source kinds:
        - currentDateTime
        - jsonAPI
        - literalText

        Source contract:
        - currentDateTime uses timeZones: [{ label, identifier }]
        - jsonAPI uses url, optional jsonPath, optional resultShape (single|collection), optional sortBy, optional sortAscending, optional limit
        - literalText is only for text widgets and should usually set text.literalContent
        - jsonAPI url must be a static HTTPS URL

        Widget-specific plan sections:
        - text widgets use text { contentField?, literalContent?, markdown?, showTimeZone?, includeSeconds? }
        - statCard and priceCard use metric { valueField, changeField?, changePercentField?, changeIsPercent?, prefix?, suffix?, footnote? }
        - list widgets use list { variant?, labelField, valueField?, subtitleField?, badgeField?, captionField?, iconField?, linkField?, maxItems? }
        - table widgets use table { columns: [{ field, header, prefix? }], maxRows? }
        - chart widgets use chart { xField, yField?, series?, color?, yPrefix?, yUnit?, showPoints? }

        Practical guidance:
        - Use currentDateTime for clocks and timezone widgets
        - Use jsonAPI for prices, exchange rates, weather, rankings, feeds, tables, and charts
        - Prefer free public JSON APIs and avoid scraping
        - For subreddit post prompts, prefer canonical Reddit listing URLs like https://www.reddit.com/r/<subreddit>/top.json?raw_json=1&limit=5&t=day and parse posts from data.children
        - If widgetType is list, always fill the list section and always provide at least list.labelField
        - For lists, use compact for simple summaries, ranked for leaderboards/watchlists, feed for headlines/updates, agenda for schedules, and cards for richer multi-line items
        - For single-value widgets backed by collections, set resultShape to collection and use limit 1 or a jsonPath that narrows to one item
        - For Hacker News or front-page headline prompts, prefer https://hn.algolia.com/api/v1/search?tags=front_page with jsonPath "hits" and fields like title, url, points, and author
        - For charts, prefer clean field names and explicit series labels

        Hard rules:
        - Output only the WidgetPlan
        - Use exact field names from the plan contract
        - Do not invent source kinds
        - Do not invent undocumented API URL patterns
        - Do not emit skill names, output keys, or returns
        - prompt must echo the original user request
        """
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
