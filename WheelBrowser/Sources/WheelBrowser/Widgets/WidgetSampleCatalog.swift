import Foundation

struct WidgetSampleDefinition: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let badge: String
    let promptHint: String?
    let buildManifest: () -> WidgetManifest
}

enum WidgetSampleCatalog {
    static let quickStart: [WidgetSampleDefinition] = [
        WidgetSampleDefinition(
            id: "bitcoin-price",
            title: "Bitcoin Price",
            subtitle: "Live CoinGecko price with 24h change.",
            badge: "Live API",
            promptHint: "Show me Bitcoin price and 24h change",
            buildManifest: bitcoinPriceManifest
        ),
        WidgetSampleDefinition(
            id: "usd-eur-rate",
            title: "USD to EUR",
            subtitle: "Live exchange rate from Frankfurter.",
            badge: "Live API",
            promptHint: "Show me the USD to EUR exchange rate",
            buildManifest: usdToEurManifest
        ),
        WidgetSampleDefinition(
            id: "utc-clock",
            title: "UTC Clock",
            subtitle: "Local time widget with the compact clock treatment.",
            badge: "Local",
            promptHint: "Create a UTC clock widget",
            buildManifest: utcClockManifest
        ),
        WidgetSampleDefinition(
            id: "amd-trend",
            title: "AMD Trend",
            subtitle: "Live 30-day AMD price history as a simple line chart.",
            badge: "Live API",
            promptHint: "Show me AMD stock price over the last 30 days as a line chart",
            buildManifest: amdTrendManifest
        ),
        WidgetSampleDefinition(
            id: "welcome-note",
            title: "Welcome Note",
            subtitle: "Local widget with no AI and no network.",
            badge: "Local",
            promptHint: "Create a markdown welcome note",
            buildManifest: welcomeNoteManifest
        ),
        WidgetSampleDefinition(
            id: "daily-agenda",
            title: "Daily Agenda",
            subtitle: "Local list widget with times, badges, and notes.",
            badge: "Local",
            promptHint: "Create an agenda list widget for my day",
            buildManifest: dailyAgendaManifest
        ),
    ]

    private static func bitcoinPriceManifest() -> WidgetManifest {
        WidgetManifest(
            widgetType: .statCard,
            config: .statCard(
                StatCardConfig(
                    title: "Bitcoin",
                    valueField: "price",
                    prefix: "$",
                    suffix: nil,
                    changeField: "change24h",
                    changeIsPercent: true
                )
            ),
            skillChain: [
                WidgetSkillStep(
                    step: 1,
                    skill: .fetchUrl,
                    params: [
                        "url": AnyCodable("https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd&include_24hr_change=true"),
                    ],
                    outputKey: "raw"
                ),
                WidgetSkillStep(
                    step: 2,
                    skill: .parseJson,
                    params: [
                        "json": AnyCodable("$raw"),
                        "path": AnyCodable("bitcoin"),
                    ],
                    outputKey: "quote"
                ),
                WidgetSkillStep(
                    step: 3,
                    skill: .transform,
                    params: [
                        "data": AnyCodable("$quote"),
                        "mapping": AnyCodable([
                            "price": "expr:item.usd.toFixed(2)",
                            "change24h": "expr:item.usd_24h_change.toFixed(2)",
                        ]),
                    ],
                    outputKey: "cardData"
                ),
            ],
            returns: "cardData",
            ttl: 300,
            prompt: "Bitcoin price demo"
        )
    }

    private static func usdToEurManifest() -> WidgetManifest {
        WidgetManifest(
            widgetType: .statCard,
            config: .statCard(
                StatCardConfig(
                    title: "USD to EUR",
                    valueField: "rate",
                    prefix: nil,
                    suffix: " EUR",
                    changeField: nil,
                    changeIsPercent: nil
                )
            ),
            skillChain: [
                WidgetSkillStep(
                    step: 1,
                    skill: .fetchUrl,
                    params: [
                        "url": AnyCodable("https://api.frankfurter.app/latest?from=USD&to=EUR"),
                    ],
                    outputKey: "raw"
                ),
                WidgetSkillStep(
                    step: 2,
                    skill: .parseJson,
                    params: [
                        "json": AnyCodable("$raw"),
                    ],
                    outputKey: "response"
                ),
                WidgetSkillStep(
                    step: 3,
                    skill: .transform,
                    params: [
                        "data": AnyCodable("$response"),
                        "mapping": AnyCodable([
                            "rate": "expr:item.rates.EUR.toFixed(4)",
                        ]),
                    ],
                    outputKey: "rateData"
                ),
            ],
            returns: "rateData",
            ttl: 3600,
            prompt: "USD to EUR demo"
        )
    }

    private static func welcomeNoteManifest() -> WidgetManifest {
        WidgetManifest(
            widgetType: .text,
            config: .text(
                TextConfig(
                    title: "Welcome",
                    markdown: true
                )
            ),
            skillChain: [
                WidgetSkillStep(
                    step: 1,
                    skill: .transform,
                    params: [
                        "data": AnyCodable([
                            "content": """
                            **Widget runtime is working**

                            This sample skipped AI generation and loaded directly from the new dashboard pipeline.
                            """
                        ]),
                        "mapping": AnyCodable([
                            "content": "content",
                        ]),
                    ],
                    outputKey: "textData"
                ),
            ],
            returns: "textData",
            ttl: 0,
            prompt: "Welcome sample"
        )
    }

    private static func utcClockManifest() -> WidgetManifest {
        WidgetManifest(
            widgetType: .text,
            config: .text(
                TextConfig(
                    title: "UTC Clock",
                    markdown: false
                )
            ),
            skillChain: [
                WidgetSkillStep(
                    step: 1,
                    skill: .currentDateTime,
                    params: [
                        "timeZone": AnyCodable("UTC"),
                        "label": AnyCodable("UTC"),
                        "showTimeZone": AnyCodable(true),
                        "includeSeconds": AnyCodable(true),
                    ],
                    outputKey: "clock"
                ),
            ],
            returns: "clock",
            ttl: 0,
            prompt: "UTC clock sample"
        )
    }

    private static func amdTrendManifest() -> WidgetManifest {
        WidgetPromptTemplateFactory.makeStockTrendManifest(
            symbol: "AMD",
            title: "AMD Price (30D)",
            prompt: "AMD trend sample",
            rangeLabel: "30D",
            pointLimit: 30,
            color: "#ff6b35"
        )
    }

    private static func dailyAgendaManifest() -> WidgetManifest {
        WidgetManifest(
            widgetType: .list,
            config: .list(
                ListConfig(
                    title: "Today",
                    labelField: "title",
                    valueField: "time",
                    subtitleField: "location",
                    badgeField: "status",
                    captionField: "note",
                    iconField: nil,
                    linkField: nil,
                    maxItems: 4,
                    variant: .agenda
                )
            ),
            skillChain: [
                WidgetSkillStep(
                    step: 1,
                    skill: .transform,
                    params: [
                        "data": AnyCodable([
                            [
                                "title": "Product review",
                                "time": "9:30 AM",
                                "location": "Design Studio",
                                "status": "Next",
                                "note": "Finalize the dashboard launch checklist.",
                            ],
                            [
                                "title": "Customer sync",
                                "time": "11:00 AM",
                                "location": "Zoom",
                                "status": "Live",
                                "note": "Capture requested list-widget workflows.",
                            ],
                            [
                                "title": "Deep work",
                                "time": "2:00 PM",
                                "location": "Library",
                                "status": "Focus",
                                "note": "Refine manifest validation and renderer polish.",
                            ],
                            [
                                "title": "Dinner",
                                "time": "7:00 PM",
                                "location": "Outer Sunset",
                                "status": "Later",
                                "note": "Take a break after shipping the widget fixes.",
                            ],
                        ]),
                        "mapping": AnyCodable([
                            "title": "title",
                            "time": "time",
                            "location": "location",
                            "status": "status",
                            "note": "note",
                        ]),
                    ],
                    outputKey: "agendaItems"
                ),
            ],
            returns: "agendaItems",
            ttl: 0,
            prompt: "Daily agenda sample"
        )
    }
}
