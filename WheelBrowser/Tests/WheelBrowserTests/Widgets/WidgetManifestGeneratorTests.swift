import Foundation
import FoundationModels
import Testing
@testable import WheelBrowser

@Suite("WidgetManifestGenerator")
struct WidgetManifestGeneratorTests {
    @Test("Generator converts structured response into validated manifest")
    func generatesManifest() async throws {
        let generator = OnDeviceWidgetManifestGenerator { _, _ in
            GeneratedWidgetManifest(
                id: "22222222-2222-2222-2222-222222222222",
                version: "1",
                widgetType: "text",
                config: GeneratedContent(GeneratedTextConfig(title: "Greeting", markdown: false)),
                skillChain: [
                    GeneratedWidgetSkillStep(
                        step: 1,
                        skill: "transform",
                        params: GeneratedContent(
                            GeneratedTransformParams(
                                data: GeneratedTextData(content: "Hello"),
                                mapping: GeneratedTextMapping(content: "content")
                            )
                        ),
                        outputKey: "textData"
                    ),
                ],
                returns: "textData",
                ttl: 300,
                prompt: "Show hello"
            )
        }

        let manifest = try await generator.generate(prompt: "Show hello")
        #expect(manifest.id == UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        #expect(manifest.widgetType == WidgetType.text)
        #expect(manifest.returns == "textData")
    }

    @Test("Generator surfaces validation errors")
    func validationFailure() async {
        let generator = OnDeviceWidgetManifestGenerator { _, _ in
            GeneratedWidgetManifest(
                id: nil,
                version: "1",
                widgetType: "text",
                config: GeneratedContent(GeneratedTextConfig(title: "Broken", markdown: false)),
                skillChain: [
                    GeneratedWidgetSkillStep(
                        step: 1,
                        skill: "transform",
                        params: GeneratedContent(
                            GeneratedTransformParams(
                                data: GeneratedTextData(content: "Hello"),
                                mapping: GeneratedTextMapping(content: "content")
                            )
                        ),
                        outputKey: "textData"
                    ),
                ],
                returns: "missing",
                ttl: 300,
                prompt: "Broken"
            )
        }

        await #expect(throws: WidgetManifestGenerationError.validationFailed("Widget returns 'missing' does not match any skill output.")) {
            try await generator.generate(prompt: "Broken")
        }
    }

    @Test("Generator normalizes common widget and skill aliases")
    func normalizesAliases() async throws {
        let generator = OnDeviceWidgetManifestGenerator { _, _ in
            GeneratedWidgetManifest(
                id: nil,
                version: "1",
                widgetType: "stat_card",
                config: GeneratedContent(
                    GeneratedLooseStatCardConfig(
                        heading: "Bitcoin",
                        value: "price"
                    )
                ),
                skillChain: [
                    GeneratedWidgetSkillStep(
                        step: 1,
                        skill: "map",
                        params: GeneratedContent(
                            GeneratedLooseTransformParams(
                                input: GeneratedLooseStatData(price: "45000"),
                                map: GeneratedLooseStatMapping(value: "price")
                            )
                        ),
                        outputKey: "cardData"
                    ),
                ],
                returns: "cardData",
                ttl: 300,
                prompt: nil
            )
        }

        let manifest = try await generator.generate(prompt: "Show me bitcoin price")
        #expect(manifest.widgetType == .statCard)
        #expect(manifest.skillChain.first?.skill == .transform)

        guard case .statCard(let config) = manifest.config else {
            Issue.record("Expected statCard config")
            return
        }

        #expect(config.title == "Bitcoin")
        #expect(config.valueField == "price")
        #expect(manifest.prompt == "Show me bitcoin price")
    }

    @Test("Generator repairs an invalid first manifest")
    func repairsInvalidManifest() async throws {
        let sequence = ManifestSequence(responses: [
            GeneratedWidgetManifest(
                id: nil,
                version: "2",
                widgetType: "text",
                config: GeneratedContent(GeneratedTextConfig(title: "Broken", markdown: false)),
                skillChain: [
                    GeneratedWidgetSkillStep(
                        step: 1,
                        skill: "transform",
                        params: GeneratedContent(
                            GeneratedTransformParams(
                                data: GeneratedTextData(content: "Hello"),
                                mapping: GeneratedTextMapping(content: "content")
                            )
                        ),
                        outputKey: "textData"
                    ),
                ],
                returns: "textData",
                ttl: 300,
                prompt: "Broken"
            ),
            GeneratedWidgetManifest(
                id: nil,
                version: "1",
                widgetType: "text",
                config: GeneratedContent(GeneratedTextConfig(title: "Fixed", markdown: false)),
                skillChain: [
                    GeneratedWidgetSkillStep(
                        step: 1,
                        skill: "transform",
                        params: GeneratedContent(
                            GeneratedTransformParams(
                                data: GeneratedTextData(content: "Hello"),
                                mapping: GeneratedTextMapping(content: "content")
                            )
                        ),
                        outputKey: "textData"
                    ),
                ],
                returns: "textData",
                ttl: 300,
                prompt: "Fixed"
            ),
        ])

        let generator = OnDeviceWidgetManifestGenerator { _, _ in
            try await sequence.next()
        }

        let manifest = try await generator.generate(prompt: "Show hello")
        #expect(manifest.version == "1")
        #expect(manifest.prompt == "Fixed")
        #expect(await sequence.callCount == 2)
    }

    @Test("Generator uses a built-in clock template for timezone prompts")
    func usesClockTemplate() async throws {
        let generator = OnDeviceWidgetManifestGenerator(
            completionProvider: { _, _ in
                Issue.record("Clock template should bypass the language model.")
                throw TestSequenceError.depleted
            },
            availabilityProvider: {
                Issue.record("Clock template should not check model availability.")
                return .unavailable("Should not be called")
            }
        )

        let manifest = try await generator.generate(prompt: "Create a PST clock widget")

        #expect(manifest.widgetType == WidgetType.text)
        #expect(manifest.skillChain.count == 1)
        #expect(manifest.skillChain.first?.skill == WidgetSkillName.currentDateTime)
        #expect(manifest.skillChain.first?.params["timeZone"]?.stringValue == "America/Los_Angeles")
        #expect(manifest.returns == "clock")

        guard case .text(let config) = manifest.config else {
            Issue.record("Expected text config")
            return
        }

        #expect(config.title == "Pacific Clock")
        #expect(config.markdown == false)
    }

    @Test("Generator builds multi-clock widgets from one prompt")
    func buildsMultiClockTemplate() async throws {
        let generator = OnDeviceWidgetManifestGenerator(
            completionProvider: { _, _ in
                Issue.record("Clock template should bypass the language model.")
                throw TestSequenceError.depleted
            },
            availabilityProvider: {
                Issue.record("Clock template should not check model availability.")
                return .unavailable("Should not be called")
            }
        )

        let manifest = try await generator.generate(prompt: "Create a widget with PST and Beijing time")

        #expect(manifest.widgetType == WidgetType.list)
        #expect(manifest.skillChain.count == 3)
        #expect(manifest.skillChain[0].skill == WidgetSkillName.currentDateTime)
        #expect(manifest.skillChain[0].params["timeZone"]?.stringValue == "America/Los_Angeles")
        #expect(manifest.skillChain[1].params["timeZone"]?.stringValue == "Asia/Shanghai")
        #expect(manifest.skillChain[2].skill == WidgetSkillName.transform)
        #expect(manifest.returns == "clockList")

        guard case .list(let config) = manifest.config else {
            Issue.record("Expected list config")
            return
        }

        #expect(config.title == "Pacific and Beijing")
        #expect(config.labelField == "label")
        #expect(config.valueField == "time")
    }

    @Test("Generator repairs placeholder output keys and refs")
    func normalizesPlaceholderRefs() async throws {
        let generator = OnDeviceWidgetManifestGenerator { _, _ in
            GeneratedWidgetManifest(
                id: nil,
                version: "1",
                widgetType: "text",
                config: GeneratedContent(
                    GeneratedBrokenTextConfig(
                        title: "Clock",
                        markdown: "false"
                    )
                ),
                skillChain: [
                    GeneratedWidgetSkillStep(
                        step: 1,
                        skill: "transform",
                        params: GeneratedContent(
                            GeneratedTransformParams(
                                data: GeneratedTextData(content: "Hello"),
                                mapping: GeneratedTextMapping(content: "content")
                            )
                        ),
                        outputKey: "$outputKey.rawText"
                    ),
                    GeneratedWidgetSkillStep(
                        step: 2,
                        skill: "transform",
                        params: GeneratedContent(
                            GeneratedRefTransformParams(
                                data: "$outputKey.rawText",
                                mapping: GeneratedTextMapping(content: "content")
                            )
                        ),
                        outputKey: "$outputKey.textData"
                    ),
                ],
                returns: "$outputKey.textData",
                ttl: 300,
                prompt: "Show hello"
            )
        }

        let manifest = try await generator.generate(prompt: "Show hello")

        #expect(manifest.skillChain[0].outputKey == "rawText")
        #expect(manifest.skillChain[1].outputKey == "textData")
        #expect(manifest.skillChain[1].params["data"]?.stringValue == "$rawText")
        #expect(manifest.returns == "textData")

        guard case .text(let config) = manifest.config else {
            Issue.record("Expected text config")
            return
        }

        #expect(config.markdown == false)
    }
}

@Generable(description: "Generated text config for widget tests.")
private struct GeneratedTextConfig {
    let title: String
    let markdown: Bool
}

@Generable(description: "Generated transform params for widget tests.")
private struct GeneratedTransformParams {
    let data: GeneratedTextData
    let mapping: GeneratedTextMapping
}

@Generable(description: "Generated text data for widget tests.")
private struct GeneratedTextData {
    let content: String
}

@Generable(description: "Generated text mapping for widget tests.")
private struct GeneratedTextMapping {
    let content: String
}

@Generable(description: "Broken text config that uses a string markdown field.")
private struct GeneratedBrokenTextConfig {
    let title: String
    let markdown: String
}

@Generable(description: "Transform params with a string data ref.")
private struct GeneratedRefTransformParams {
    let data: String
    let mapping: GeneratedTextMapping
}

@Generable(description: "Loose stat card config for alias normalization tests.")
private struct GeneratedLooseStatCardConfig {
    let heading: String
    let value: String
}

@Generable(description: "Loose transform params for alias normalization tests.")
private struct GeneratedLooseTransformParams {
    let input: GeneratedLooseStatData
    let map: GeneratedLooseStatMapping
}

@Generable(description: "Loose stat data for alias normalization tests.")
private struct GeneratedLooseStatData {
    let price: String
}

@Generable(description: "Loose stat mapping for alias normalization tests.")
private struct GeneratedLooseStatMapping {
    let value: String
}

private actor ManifestSequence {
    private var responses: [GeneratedWidgetManifest]
    private(set) var callCount = 0

    init(responses: [GeneratedWidgetManifest]) {
        self.responses = responses
    }

    func next() throws -> GeneratedWidgetManifest {
        callCount += 1
        guard !responses.isEmpty else {
            throw TestSequenceError.depleted
        }
        return responses.removeFirst()
    }
}

private enum TestSequenceError: Error {
    case depleted
}
