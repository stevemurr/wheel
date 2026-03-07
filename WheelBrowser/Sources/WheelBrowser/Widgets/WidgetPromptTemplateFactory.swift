import Foundation

enum WidgetPromptTemplateFactory {
    static func manifest(for prompt: String) -> WidgetManifest? {
        guard let intent = ClockIntent(prompt: prompt) else {
            return nil
        }

        if intent.locations.count <= 1 {
            return singleClockManifest(for: intent)
        }

        return multiClockManifest(for: intent)
    }

    private static func singleClockManifest(for intent: ClockIntent) -> WidgetManifest {
        let location = intent.locations.first
        var params: [String: AnyCodable] = [
            "showTimeZone": AnyCodable(true),
            "includeSeconds": AnyCodable(true),
        ]

        if let location {
            params["timeZone"] = AnyCodable(location.identifier)
            params["label"] = AnyCodable(location.label)
        }

        return WidgetManifest(
            widgetType: .text,
            config: .text(
                TextConfig(
                    title: location?.singleTitle ?? "Clock",
                    markdown: false
                )
            ),
            skillChain: [
                WidgetSkillStep(
                    step: 1,
                    skill: .currentDateTime,
                    params: params,
                    outputKey: "clock"
                ),
            ],
            returns: "clock",
            ttl: 0,
            prompt: intent.prompt
        )
    }

    private static func multiClockManifest(for intent: ClockIntent) -> WidgetManifest {
        let locations = intent.locations
        var skillChain: [WidgetSkillStep] = []

        for (index, location) in locations.enumerated() {
            skillChain.append(
                WidgetSkillStep(
                    step: index + 1,
                    skill: .currentDateTime,
                    params: [
                        "timeZone": AnyCodable(location.identifier),
                        "label": AnyCodable(location.label),
                        "showTimeZone": AnyCodable(true),
                        "includeSeconds": AnyCodable(true),
                    ],
                    outputKey: "\(location.outputKeyPrefix)Clock"
                )
            )
        }

        let dataRefs = locations.map { "$\($0.outputKeyPrefix)Clock" }
        skillChain.append(
            WidgetSkillStep(
                step: skillChain.count + 1,
                skill: .transform,
                params: [
                    "data": AnyCodable(dataRefs),
                    "mapping": AnyCodable([
                        "label": "label",
                        "time": "formatted",
                        "timeZone": "timeZoneAbbreviation",
                    ]),
                ],
                outputKey: "clockList"
            )
        )

        return WidgetManifest(
            widgetType: .list,
            config: .list(
                ListConfig(
                    title: multiClockTitle(for: locations),
                    labelField: "label",
                    valueField: "time",
                    subtitleField: "timeZone",
                    badgeField: nil,
                    captionField: nil,
                    iconField: nil,
                    linkField: nil,
                    maxItems: locations.count,
                    variant: .compact
                )
            ),
            skillChain: skillChain,
            returns: "clockList",
            ttl: 0,
            prompt: intent.prompt
        )
    }

    private static func multiClockTitle(for locations: [ClockLocation]) -> String {
        let labels = locations.map(\.label)
        if labels.count == 2 {
            return "\(labels[0]) and \(labels[1])"
        }
        if labels.count == 3 {
            return "\(labels[0]), \(labels[1]), and \(labels[2])"
        }
        return "World Clocks"
    }
}

private struct ClockIntent {
    let prompt: String
    let locations: [ClockLocation]

    init?(prompt: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrompt = ClockLocation.normalize(trimmedPrompt)
        let locations = Self.deduplicate(ClockLocation.catalog.filter { $0.matches(in: normalizedPrompt) })

        let hasExplicitClockIntent = Self.containsClockIntent(in: normalizedPrompt)
        let mentionsTimeWord = Self.containsWord("time", in: normalizedPrompt)
            || Self.containsWord("times", in: normalizedPrompt)
        guard hasExplicitClockIntent || (!locations.isEmpty && mentionsTimeWord) else {
            return nil
        }

        self.prompt = trimmedPrompt
        self.locations = locations
    }

    private static func containsClockIntent(in prompt: String) -> Bool {
        containsWord("clock", in: prompt)
            || containsPhrase("current time", in: prompt)
            || containsPhrase("time now", in: prompt)
            || containsPhrase("time in", in: prompt)
            || containsPhrase("times in", in: prompt)
            || containsPhrase("world clock", in: prompt)
    }

    private static func containsWord(_ word: String, in prompt: String) -> Bool {
        prompt == word
            || prompt.hasPrefix("\(word) ")
            || prompt.hasSuffix(" \(word)")
            || prompt.contains(" \(word) ")
    }

    private static func containsPhrase(_ phrase: String, in prompt: String) -> Bool {
        prompt.contains(phrase)
    }

    private static func deduplicate(_ locations: [ClockLocation]) -> [ClockLocation] {
        var seen = Set<ClockLocation>()
        var result: [ClockLocation] = []
        for location in locations where seen.insert(location).inserted {
            result.append(location)
        }
        return result
    }
}

private struct ClockLocation: Hashable {
    let label: String
    let singleTitle: String
    let identifier: String
    let aliases: [String]

    var outputKeyPrefix: String {
        label
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .filter { $0.isLetter || $0.isNumber }
    }

    func matches(in prompt: String) -> Bool {
        aliases.contains { alias in
            Self.contains(alias: alias, in: prompt)
        }
    }

    private static func contains(alias: String, in prompt: String) -> Bool {
        let normalizedAlias = normalize(alias)
        if normalizedAlias.contains(" ") || normalizedAlias.contains("/") {
            return prompt.contains(normalizedAlias)
        }

        return prompt == normalizedAlias
            || prompt.hasPrefix("\(normalizedAlias) ")
            || prompt.hasSuffix(" \(normalizedAlias)")
            || prompt.contains(" \(normalizedAlias) ")
    }

    static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(
                of: #"[^a-z0-9/ ]+"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let catalog: [ClockLocation] = [
        ClockLocation(
            label: "Pacific",
            singleTitle: "Pacific Clock",
            identifier: "America/Los_Angeles",
            aliases: ["pst", "pdt", "pt", "pacific", "pacific time", "los angeles", "san francisco", "seattle"]
        ),
        ClockLocation(
            label: "Mountain",
            singleTitle: "Mountain Clock",
            identifier: "America/Denver",
            aliases: ["mst", "mdt", "mt", "mountain", "mountain time", "denver", "phoenix"]
        ),
        ClockLocation(
            label: "Central",
            singleTitle: "Central Clock",
            identifier: "America/Chicago",
            aliases: ["cst", "cdt", "ct", "central", "central time", "chicago", "dallas", "austin"]
        ),
        ClockLocation(
            label: "Eastern",
            singleTitle: "Eastern Clock",
            identifier: "America/New_York",
            aliases: ["est", "edt", "et", "eastern", "eastern time", "new york", "nyc", "boston", "miami"]
        ),
        ClockLocation(
            label: "Beijing",
            singleTitle: "Beijing Clock",
            identifier: "Asia/Shanghai",
            aliases: ["beijing", "china", "china time", "china standard time", "cst china", "shanghai"]
        ),
        ClockLocation(
            label: "Tokyo",
            singleTitle: "Tokyo Clock",
            identifier: "Asia/Tokyo",
            aliases: ["tokyo", "jst", "japan", "japan time"]
        ),
        ClockLocation(
            label: "Seoul",
            singleTitle: "Seoul Clock",
            identifier: "Asia/Seoul",
            aliases: ["seoul", "kst", "korea", "korea time"]
        ),
        ClockLocation(
            label: "Singapore",
            singleTitle: "Singapore Clock",
            identifier: "Asia/Singapore",
            aliases: ["singapore", "sgt", "singapore time"]
        ),
        ClockLocation(
            label: "London",
            singleTitle: "London Clock",
            identifier: "Europe/London",
            aliases: ["london", "uk", "uk time", "british time", "gmt"]
        ),
        ClockLocation(
            label: "Paris",
            singleTitle: "Paris Clock",
            identifier: "Europe/Paris",
            aliases: ["paris", "france", "france time", "cet", "cest"]
        ),
        ClockLocation(
            label: "Berlin",
            singleTitle: "Berlin Clock",
            identifier: "Europe/Berlin",
            aliases: ["berlin", "germany", "germany time"]
        ),
        ClockLocation(
            label: "Sydney",
            singleTitle: "Sydney Clock",
            identifier: "Australia/Sydney",
            aliases: ["sydney", "aest", "aedt", "australia", "australia time"]
        ),
        ClockLocation(
            label: "UTC",
            singleTitle: "UTC Clock",
            identifier: "UTC",
            aliases: ["utc", "zulu", "universal time"]
        ),
    ]
}
