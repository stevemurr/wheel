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
            id: "welcome-note",
            title: "Welcome Note",
            subtitle: "Local widget with no AI and no network.",
            badge: "Local",
            promptHint: "Create a markdown welcome note",
            buildManifest: welcomeNoteManifest
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
}
